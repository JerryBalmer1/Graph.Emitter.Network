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
        $module = InModuleScope Graph.Emitter.Network { $script:NetworkGraphNodeContract }
        foreach ($kind in $NodeContract.Keys) {
            @('Id', 'Kind', 'Name') + @($module[$kind]) + @('Source') | Should -Be $NodeContract[$kind] -Because $kind
        }
    }

    It 'edge property names equal the contract in docs/graph-shape.md' {
        $EdgeContract['Edge'] | Should -Be @('From', 'To', 'Kind', 'Source')
        foreach ($edge in $Graph.Edges) { @($edge.PSObject.Properties.Name) | Should -Be $EdgeContract['Edge'] }
    }

    It 'property order: an Interface node is Id, Kind, Name, InterfaceName, InterfaceKey, ..., Source; an edge is From, To, Kind, Source' {
        $interface = $Graph.Nodes | Where-Object Kind -eq 'Interface' | Select-Object -First 1
        @($interface.PSObject.Properties.Name) | Should -Be @('Id', 'Kind', 'Name', 'InterfaceName', 'InterfaceKey', 'Ip', 'PrefixLength', 'MacAddress', 'Vendor', 'Status', 'Source')
        $route = $Graph.Nodes | Where-Object Kind -eq 'Route' | Select-Object -First 1
        @($route.PSObject.Properties.Name) | Should -Be @('Id', 'Kind', 'Name', 'Destination', 'PrefixLength', 'NextHop', 'InterfaceName', 'InterfaceKey', 'Metric', 'Source')
        foreach ($edge in $Graph.Edges) { @($edge.PSObject.Properties.Name) | Should -Be @('From', 'To', 'Kind', 'Source') }
    }

    It 'every edge has a non-empty Source' {
        foreach ($edge in $Graph.Edges) { [string]$edge.Source | Should -Not -BeNullOrEmpty -Because "$($edge.From) $($edge.Kind) $($edge.To)" }
    }

    It 'matches ConvertTo-TerraformResourceGraph: Id and Kind first, edges From, To, Kind (then Source), graph Root, Nodes, Edges' {
        foreach ($node in $Graph.Nodes) { @($node.PSObject.Properties.Name)[0..1] | Should -Be @('Id', 'Kind') }
        foreach ($edge in $Graph.Edges) { @($edge.PSObject.Properties.Name)[0..2] | Should -Be @('From', 'To', 'Kind') }
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
        $module = @(InModuleScope Graph.Emitter.Network { $script:NetworkGraphEdgeKinds })
        ($documented -join ',') | Should -BeExactly ($module -join ',')
        foreach ($kind in $module) { $kind | Should -MatchExactly '^[A-Z][a-z]+([A-Z][a-z]+)*$' }
        InModuleScope Graph.Emitter.Network {
            $state = [pscustomobject]@{ EdgeKeys = [System.Collections.Generic.HashSet[string]]::new(); Edges = [System.Collections.Generic.List[object]]::new() }
            { Add-NetworkGraphEdge -State $state -From a -To b -Kind contains -Source fixture } | Should -Throw '*Unknown edge kind*'
        }
    }
}

Describe 'Every Source is pasteable' {
    BeforeAll {
        $script:Checked = [System.Collections.Generic.List[object]]::new()
        function Add-Source([string]$From, $Rows) {
            foreach ($row in @($Rows)) {
                if ($null -eq $row) { continue }
                foreach ($name in 'Source', 'RdapSource') {
                    if ($row.PSObject.Properties[$name] -and $row.$name) { $Checked.Add([pscustomobject]@{ From = "$From.$name"; Source = [string]$row.$name }) }
                }
                if ($row.PSObject.Properties['Answers']) { Add-Source "$From.Answers" $row.Answers }
            }
        }
        # The native tools the module wraps: every -FilePath given to Invoke-NetworkGraphNative.
        $script:Tools = @(foreach ($file in Get-ChildItem -Path $ModuleRoot -Recurse -Filter '*.ps1') {
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
                foreach ($call in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-NetworkGraphNative' }, $true)) {
                    $elements = @($call.CommandElements)
                    for ($i = 0; $i -lt $elements.Count - 1; $i++) {
                        if ($elements[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and $elements[$i].ParameterName -eq 'FilePath') { $elements[$i + 1].Value }
                    }
                }
            }) | Select-Object -Unique

        # Native tools through the seam, each with its own fixture.
        Mock Resolve-NetworkGraphTool -ModuleName Graph.Emitter.Network { $script:NextTool }
        $ip = {
            param($Arguments)
            if ($Arguments -contains 'neigh') { Get-Fixture 'ip-neigh.linux.json' }
            elseif ($Arguments -contains 'addr') { Get-Fixture 'ip-addr.linux.json' }
            elseif ($Arguments -contains '-6') { Get-Fixture 'ip-route6.linux.json' }
            else { Get-Fixture 'ip-route.linux.json' }
        }
        Set-NativeFixture -Output @{
            ping       = $IsWindows ? (Get-Fixture 'ping.windows.txt') : (Get-Fixture 'ping.linux.txt')
            tracert    = Get-Fixture 'tracert.windows.txt'
            pathping   = Get-Fixture 'pathping.windows.txt'
            mtr        = Get-Fixture 'mtr.linux.json'
            traceroute = Get-Fixture 'traceroute.linux.txt'
            nc         = Get-Fixture 'nc.linux.txt'
            ss         = Get-Fixture 'ss.linux.txt'
            ip         = $ip
            arp        = Get-Fixture 'arp.windows.txt'
            dig        = Get-Fixture 'dig.linux.txt'
            nslookup   = Get-Fixture 'nslookup.linux.txt'
            nmap       = Get-Fixture 'nmap.linux.xml'
            curl       = { param($Arguments) ($Arguments[-1] -like '*ipify*') ? '{"ip":"203.0.113.7"}' : '203.0.113.7' }
        }
        $native = [ordered]@{
            'ping'       = { Test-NetworkPath 1.1.1.1 -Count 3 -Tool Native }
            'tracert'    = { Trace-NetworkPath 1.1.1.1 -MaxHops 12 -Tool Native -NativeTool tracert }
            'pathping'   = { Trace-NetworkPath 1.1.1.1 -MaxHops 8 -Tool Native -NativeTool pathping }
            'mtr'        = { Trace-NetworkPath 1.1.1.1 -MaxHops 12 -Tool Native -NativeTool mtr }
            'traceroute' = { Trace-NetworkPath 1.1.1.1 -MaxHops 12 -Tool Native -NativeTool traceroute }
            'nc'         = { Test-NetworkPort 1.1.1.1 -Port 443 -Tool Native }
            'ss'         = { Get-NetworkConnection -Tool Native }
            'ip route'   = { Get-NetworkRoute -Tool Native }
            'ip neigh'   = { Get-NetworkNeighbor -Tool Native }
            'ip addr'    = { Get-NetworkInterface -Tool Native }
            'arp'        = { Get-NetworkNeighbor -Tool Native }
            'dig'        = { Resolve-NetworkName example.com -Tool Native }
            'nslookup'   = { Resolve-NetworkName example.com -Tool Native }
            'curl'       = { Get-ExternalIpAddress -Tool Native }
            'nmap'       = { Invoke-NetworkScan 1.1.1.1 -Port 443 -Tool Native }
        }
        foreach ($key in $native.Keys) {
            $script:NextTool = ($key -split ' ')[0]
            Add-Source $key (& $native[$key])
        }
        $nativeRows = @(foreach ($key in 'ss', 'ip route', 'ip addr', 'tracert', 'nmap') { $script:NextTool = ($key -split ' ')[0]; & $native[$key] })

        # Get-NetworkHost on the Linux path: ufw.conf read without root, ip for interfaces and routes.
        $conf = Join-Path $TestDrive 'ufw.conf'
        Set-Content -LiteralPath $conf -Value (Get-Fixture 'ufw.conf.linux.txt') -NoNewline
        InModuleScope Graph.Emitter.Network -Parameters @{ Conf = $conf } { param($Conf) $script:NetworkGraphPlatform = 'Linux'; $script:NetworkGraphUfwConfPath = $Conf }
        $script:NextTool = 'ip'
        $hostRow = Get-NetworkHost -Tool Native
        Add-Source 'Get-NetworkHost (Linux)' $hostRow
        InModuleScope Graph.Emitter.Network { $script:NetworkGraphPlatform = $IsWindows ? 'Windows' : ($IsLinux ? 'Linux' : 'macOS'); $script:NetworkGraphUfwConfPath = '/etc/ufw/ufw.conf' }

        # Windows cmdlets, replaced by their fixtures (they exist only on Windows).
        if ($IsWindows) {
            $windowsKeys = Get-TestKeyMap -Platform Windows
            Mock Get-NetworkGraphInterfaceKeyMap -ModuleName Graph.Emitter.Network { $windowsKeys }.GetNewClosure()
            Mock Get-NetTCPConnection -ModuleName Graph.Emitter.Network { Get-FixtureJson 'Get-NetTCPConnection.windows.json' }
            Mock Get-NetUDPEndpoint -ModuleName Graph.Emitter.Network { Get-FixtureJson 'Get-NetUDPEndpoint.windows.json' }
            Mock Get-NetRoute -ModuleName Graph.Emitter.Network { Get-FixtureJson 'Get-NetRoute.windows.json' }
            Mock Get-NetNeighbor -ModuleName Graph.Emitter.Network { Get-FixtureJson 'Get-NetNeighbor.windows.json' }
            Mock Get-NetworkGraphNetIPConfiguration -ModuleName Graph.Emitter.Network { Get-FixtureJson 'Get-NetIPConfiguration.windows.json' }
            Mock Resolve-DnsName -ModuleName Graph.Emitter.Network { Get-FixtureJson 'Resolve-DnsName.windows.json' }
            Mock Test-NetConnection -ModuleName Graph.Emitter.Network { (Get-FixtureJson 'Test-NetConnection.windows.json')[0] }
            Mock Get-NetFirewallProfile -ModuleName Graph.Emitter.Network { Get-FixtureJson 'Get-NetFirewallProfile.windows.json' }
            Mock Get-NetworkGraphFirewallProduct -ModuleName Graph.Emitter.Network { Get-FixtureJson 'FirewallProduct.windows.json' }
            $cmdlets = [ordered]@{
                'Get-NetTCPConnection'   = { Get-NetworkConnection -Tool Native }
                'Get-NetRoute'           = { Get-NetworkRoute -Tool Native }
                'Get-NetNeighbor'        = { Get-NetworkNeighbor -Tool Native }
                'Get-NetIPConfiguration' = { Get-NetworkInterface -Tool Native }
                'Resolve-DnsName'        = { Resolve-NetworkName example.com -Tool Native }
                'Test-NetConnection'     = { Test-NetworkPort 1.1.1.1 -Port 443 -Tool Native }
            }
            foreach ($key in $cmdlets.Keys) {
                $script:NextTool = $key
                Add-Source $key (& $cmdlets[$key])
            }
            $script:NextTool = 'Get-NetIPConfiguration'
            Add-Source 'Get-NetworkHost (Windows)' (Get-NetworkHost -Tool Native)
        }
        Clear-NativeFixture

        # .NET floors: in-process reads and loopback only; nothing leaves the host.
        $script:NextTool = 'DotNet'
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        try {
            $port = $listener.LocalEndpoint.Port
            Add-Source 'Test-NetworkPort DotNet Tcp' (Test-NetworkPort 127.0.0.1 -Port $port -Tool DotNet)
            Add-Source 'Test-NetworkPort DotNet Udp' (Test-NetworkPort 127.0.0.1 -Port $port -Protocol Udp -Timeout 300 -Tool DotNet)
            Add-Source 'Invoke-NetworkScan DotNet' (Invoke-NetworkScan 127.0.0.1 -Port $port -Timeout 500 -Tool DotNet)
        }
        finally { $listener.Stop() }
        Add-Source 'Get-NetworkConnection DotNet' (Get-NetworkConnection -Tool DotNet | Group-Object Source | ForEach-Object { $_.Group[0] })
        Add-Source 'Get-NetworkRoute DotNet' (Get-NetworkRoute -Tool DotNet | Select-Object -First 1)
        Add-Source 'Get-NetworkInterface DotNet' (Get-NetworkInterface -Tool DotNet | Select-Object -First 1)
        Add-Source 'Resolve-NetworkName DotNet' (Resolve-NetworkName localhost -Type A -Tool DotNet)
        Mock Get-NetworkGraphDotNetTrace -ModuleName Graph.Emitter.Network { [pscustomobject]@{ Hop = 1; Ip = '127.0.0.1'; Host = $null; RttMs = @(0.1); AvgMs = 0.1; LossPercent = 0; Responded = $true } }
        Add-Source 'Trace-NetworkPath DotNet' (Trace-NetworkPath 127.0.0.1 -MaxHops 3 -Tool DotNet)
        if ($IsWindows) { Add-Source 'Test-NetworkPath DotNet' (Test-NetworkPath 127.0.0.1 -Count 1 -Tool DotNet) }
        if ($IsLinux) { Add-Source 'Get-NetworkNeighbor DotNet' (Get-NetworkNeighbor -Tool DotNet -IncludeUnresolved | Select-Object -First 1) }
        Set-WebFixture -Content @{
            'https://api.ipify.org?format=json' = '{"ip":"20.128.0.10"}'
            'https://checkip.amazonaws.com'     = '20.128.0.10'
            'https://icanhazip.com'             = '20.128.0.10'
            'https://rdap.org/ip/20.128.0.10'   = Get-Fixture 'rdap-arin.json'
        }
        Add-Source 'Get-ExternalIpAddress DotNet -Rdap' (Get-ExternalIpAddress -Rdap -Tool DotNet)
        Clear-NativeFixture

        # Data verdicts, and the graph built from all of the above.
        $prefixes = (Get-NetworkGraphData -Kind CloudRanges).Data['prefixes']
        $azureKey = $prefixes.Keys | Where-Object { -not $_.Contains(':') -and @($prefixes[$_])[0][0] -eq 'Azure' } | Select-Object -First 1
        $verdicts = @(Test-IPAddress ($azureKey.Split('/')[0]), 1.1.1.1)
        Add-Source 'Test-IPAddress' $verdicts
        $graphInput = @($hostRow) + $nativeRows + $verdicts + @(New-SubnetPlan 10.0.0.0/22 -Hosts 250, 120 -Cloud Azure) + @(Get-Subnet 10.1.0.0/24)
        $graph = $graphInput | ConvertTo-NetworkGraph -WarningAction SilentlyContinue
        foreach ($node in $graph.Nodes) { Add-Source "node $($node.Kind)" $node }
        foreach ($edge in $graph.Edges) { Add-Source "edge $($edge.Kind)" $edge }
    }

    It 'each Source is a resolvable verb-noun command, a wrapped tool command line, a full-type-name .NET expression, or a data citation; every command parses' {
        $Checked.Count | Should -BeGreaterThan 40
        $citation = '^[\w.-]+\.json(\.gz)? pulled \d{4}-\d{2}-\d{2} \(https://[^)\s]+\)(; [\w.-]+\.json(\.gz)? pulled \d{4}-\d{2}-\d{2} \(https://[^)\s]+\))*$'
        $seen = @{}
        foreach ($entry in $Checked) {
            $source = $entry.Source
            if ($seen.ContainsKey($source)) { continue }
            $seen[$source] = 1
            Write-Verbose ('{0,-42} {1}' -f $entry.From, $source)
            if ($source -match $citation) { continue }
            $first = ($source -split '[\s;]+')[0]
            $isCommand = $first -match '^[A-Za-z]+-[A-Za-z]+$' -and [bool](Get-Command -Name $first -ErrorAction SilentlyContinue)
            $isTool = $first -in $Tools
            $isType = $source -match '^\[System\.[\w.]+\]::'
            ($isCommand -or $isTool -or $isType) | Should -BeTrue -Because "$($entry.From): '$source'"
            { [scriptblock]::Create($source) } | Should -Not -Throw -Because "$($entry.From): '$source'"
        }
    }
}
