BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:Graph = Get-TestGraphInput | ConvertTo-NetworkGraph -WarningAction SilentlyContinue

    # The two tables in docs/graph-shape.md: '## Node properties' (Kind | Id scheme | Properties)
    # and '## Edge properties' (Type | Properties).
    $doc = Get-Content -Raw (Join-Path $RepoRoot 'docs' 'graph-shape.md')
    function Read-Table([string]$Heading) {
        $section = ($doc -split "(?m)^## ")[1..99] | Where-Object { $_.StartsWith($Heading) } | Select-Object -First 1
        $table = [ordered]@{}
        foreach ($line in $section -split "`r?`n") {
            if ($line -notmatch '^\|' -or $line -match '^\|\s*-' -or $line -match '^\|\s*(Kind|Type)\s*\|') { continue }
            $cells = @($line.Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
            $table[$cells[0]] = @($cells[-1] -split ',\s*')
            if ($Heading -eq 'Edge properties') { break }
        }
        $table
    }
    $script:NodeContract = Read-Table 'Node properties'
    $script:EdgeContract = Read-Table 'Edge properties'
}

Describe 'Graph contract (docs/graph-shape.md)' {
    It 'documents all ten node kinds' {
        @($NodeContract.Keys) | Should -Be @('Host', 'Interface', 'Subnet', 'Route', 'Hop', 'Connection', 'Process', 'RemoteHost', 'Cloud', 'Asn')
    }

    It 'the fixture graph has every node kind' {
        @($Graph.Nodes.Kind | Select-Object -Unique | Sort-Object) | Should -Be @($NodeContract.Keys | Sort-Object)
    }

    It 'node property names equal the contract in docs/graph-shape.md' {
        foreach ($node in $Graph.Nodes) {
            @($node.PSObject.Properties.Name) | Should -Be $NodeContract[$node.Kind] -Because "$($node.Kind) node $($node.Id)"
        }
    }

    It 'the module table matches the doc table' {
        $module = InModuleScope NetworkGraph { $script:NetworkGraphNodeContract }
        foreach ($kind in $NodeContract.Keys) {
            @('Id', 'Kind', 'Name') + @($module[$kind]) + @('Source') | Should -Be $NodeContract[$kind] -Because $kind
        }
    }

    It 'edge property names equal the contract in docs/graph-shape.md' {
        $EdgeContract['Edge'] | Should -Be @('From', 'To', 'Kind')
        foreach ($edge in $Graph.Edges) { @($edge.PSObject.Properties.Name) | Should -Be $EdgeContract['Edge'] }
    }

    It 'matches ConvertTo-TerraformResourceGraph: Id and Kind first, edges From, To, Kind, graph Root, Nodes, Edges' {
        foreach ($node in $Graph.Nodes) { @($node.PSObject.Properties.Name)[0..1] | Should -Be @('Id', 'Kind') }
        @($Graph.PSObject.Properties.Name | Where-Object { $_ -in 'Root', 'Nodes', 'Edges', 'NodeCount', 'EdgeCount' }).Count | Should -Be 5
    }

    It 'gives every node a unique Id' {
        @($Graph.Nodes.Id | Group-Object | Where-Object Count -gt 1).Count | Should -Be 0
        $Graph.NodeCount | Should -Be @($Graph.Nodes.Id | Select-Object -Unique).Count
    }

    It 'has no node property named Address, Count, Length or another System.Array member' {
        $arrayMembers = @([System.Array].GetMembers().Name | Select-Object -Unique)
        foreach ($kind in $NodeContract.Keys) {
            foreach ($name in $NodeContract[$kind]) { $name | Should -Not -BeIn $arrayMembers -Because "$kind.$name" }
        }
    }

    It 'every edge joins two nodes in the graph and uses a documented kind' {
        $ids = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Graph.Nodes.Id), [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($edge in $Graph.Edges) {
            $ids.Contains($edge.From) | Should -BeTrue -Because "edge from $($edge.From)"
            $ids.Contains($edge.To) | Should -BeTrue -Because "edge to $($edge.To)"
            @('Contains', 'RoutesTo', 'HopsTo', 'ConnectsTo', 'OwnedBy', 'ResolvesTo', 'BelongsTo') -ccontains $edge.Kind | Should -BeTrue -Because "edge kind '$($edge.Kind)' (case-sensitive)"
        }
    }

    It 'edge kinds are PascalCase and the doc table, the module list and TerraformGraph agree' {
        $section = ($doc -split '(?m)^Edge kinds, From to To:')[1]
        # The table's rows: from its header to the first line that is not a table row.
        $rows = @(($section.Trim() -split "`r?`n") | ForEach-Object -Begin { $inTable = $true } -Process { if ($inTable -and $_ -match '^\|') { $_ } else { $inTable = $false } })
        $documented = @($rows | Select-Object -Skip 2 | ForEach-Object { ($_.Trim('|') -split '\|')[0].Trim() } | Select-Object -Unique)
        $module = @(InModuleScope NetworkGraph { $script:NetworkGraphEdgeKinds })
        ($documented -join ',') | Should -BeExactly ($module -join ',')
        foreach ($kind in $module) { $kind | Should -MatchExactly '^[A-Z][a-z]+([A-Z][a-z]+)*$' }
        InModuleScope NetworkGraph {
            $state = [pscustomobject]@{ EdgeKeys = [System.Collections.Generic.HashSet[string]]::new(); Edges = [System.Collections.Generic.List[object]]::new() }
            { Add-NetworkGraphEdge -State $state -From a -To b -Kind contains } | Should -Throw '*Unknown edge kind*'
        }
    }
}
