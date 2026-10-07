BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:Graph = Get-TestGraphInput | ConvertTo-NetworkGraph -WarningAction SilentlyContinue
    function Find-Node([string]$Id) { $Graph.Nodes | Where-Object Id -eq $Id }
    function Test-Edge([string]$From, [string]$To, [string]$Kind) { [bool]($Graph.Edges | Where-Object { $_.From -eq $From -and $_.To -eq $To -and $_.Kind -ceq $Kind }) }
}

Describe 'ConvertTo-NetworkGraph' {
    It 'roots the graph at the host from Get-NetworkHost' {
        $Graph.Root | Should -Be 'testhost'
        (Find-Node 'testhost').Os | Should -Be 'Ubuntu 22.04.4 LTS'
    }

    It 'uses the documented Id per kind' {
        Find-Node 'testhost/if/eth0' | Should -Not -BeNullOrEmpty
        Find-Node '172.17.0.0/16@None' | Should -Not -BeNullOrEmpty
        Find-Node '10.0.0.0/24@Azure' | Should -Not -BeNullOrEmpty
        Find-Node 'testhost/route/0.0.0.0/0/172.17.0.1/eth0' | Should -Not -BeNullOrEmpty
        Find-Node 'hop/1.1.1.1/4' | Should -Not -BeNullOrEmpty
        Find-Node 'testhost/conn/tcp/0.0.0.0:8080/*' | Should -Not -BeNullOrEmpty
        Find-Node 'testhost:1264' | Should -Not -BeNullOrEmpty
        Find-Node '1.1.1.1' | Should -Not -BeNullOrEmpty
        Find-Node 'dns:example.com' | Should -Not -BeNullOrEmpty
        Find-Node 'cloud/Azure' | Should -Not -BeNullOrEmpty
        Find-Node 'AS8075' | Should -Not -BeNullOrEmpty
    }

    It 'skips loopback interface subnets' {
        Find-Node '127.0.0.0/8@None' | Should -BeNullOrEmpty
    }

    It 'links host, interface, subnet and route with Contains and RoutesTo' {
        Test-Edge 'testhost' 'testhost/if/eth0' 'Contains' | Should -BeTrue
        Test-Edge '172.17.0.0/16@None' 'testhost/if/eth0' 'Contains' | Should -BeTrue
        Test-Edge 'testhost/if/eth0' 'testhost/route/0.0.0.0/0/172.17.0.1/eth0' 'Contains' | Should -BeTrue
        Test-Edge 'testhost/route/0.0.0.0/0/172.17.0.1/eth0' '172.17.0.1' 'RoutesTo' | Should -BeTrue
    }

    It 'links connections to processes and remote hosts' {
        $id = 'testhost/conn/tcp/172.17.0.2:44252/1.1.1.1:443'
        Test-Edge $id 'testhost:1265' 'OwnedBy' | Should -BeTrue
        Test-Edge $id '1.1.1.1' 'ConnectsTo' | Should -BeTrue
        (Find-Node 'testhost:1265').ProcessName | Should -Be 'sleep'
    }

    It 'chains trace hops from the host' {
        Test-Edge 'testhost' 'hop/1.1.1.1/1' 'HopsTo' | Should -BeTrue
        Test-Edge 'hop/1.1.1.1/6' 'hop/1.1.1.1/7' 'HopsTo' | Should -BeTrue
        (Find-Node 'hop/1.1.1.1/4').Name | Should -Be '4 *'
    }

    It 'links DNS names to addresses and names' {
        Test-Edge 'dns:example.com' '104.20.23.154' 'ResolvesTo' | Should -BeTrue
        Test-Edge 'dns:www.microsoft.com' 'dns:www.microsoft.com-c-3.edgekey.net' 'ResolvesTo' | Should -BeTrue
        Test-Edge '1.1.1.1' 'dns:one.one.one.one' 'ResolvesTo' | Should -BeTrue
    }

    It 'links a cloud address to its cloud and ASN' {
        $remote = $Graph.Nodes | Where-Object { $_.Kind -eq 'RemoteHost' -and $_.Cloud -eq 'Azure' } | Select-Object -First 1
        Test-Edge $remote.Id 'cloud/Azure' 'BelongsTo' | Should -BeTrue
        Test-Edge $remote.Id 'AS8075' 'BelongsTo' | Should -BeTrue
    }

    It 'merges open ports and names into the remote host' {
        $remote = Find-Node '1.1.1.1'
        $remote.OpenPorts | Should -Be @(443)
        $remote.RemoteHost | Should -Not -BeNullOrEmpty
    }

    It 'links a neighbour to its interface and the external address to the host' {
        Test-Edge 'testhost/if/eth0' '172.17.0.1' 'ConnectsTo' | Should -BeTrue
        Test-Edge 'testhost' '203.0.113.7' 'RoutesTo' | Should -BeTrue
        (Find-Node 'AS64496').Owner | Should -Be 'Example Networks'
    }

    It 'nests a plan''s subnets under the parent and does not call that an overlap' {
        Test-Edge '10.0.0.0/22@Azure' '10.0.0.0/24@Azure' 'Contains' | Should -BeTrue
        $Graph.Findings | Where-Object { $_.Finding -eq 'SubnetOverlap' -and $_.NodeId -eq '10.0.0.0/22@Azure' -and $_.RelatedId -eq '10.0.0.0/24@Azure' } | Should -BeNullOrEmpty
    }

    Context 'findings' {
        It 'reports <Finding> on <NodeId>' -ForEach @(
            @{ Finding = 'BelowCloudMinimum'; NodeId = '10.0.0.0/30@Azure' }
            @{ Finding = 'SubnetOverlap'; NodeId = '10.0.0.0/24@Azure' }
            @{ Finding = 'WildcardListener'; NodeId = 'testhost/conn/tcp/0.0.0.0:8080/*' }
            @{ Finding = 'NonCloudPublicConnection'; NodeId = 'testhost/conn/tcp/172.17.0.2:44252/1.1.1.1:443' }
            @{ Finding = 'RouteWithoutInterface'; NodeId = 'testhost/route/10.99.0.0/16/172.17.0.254/-' }
        ) {
            $row = $Graph.Findings | Where-Object { $_.Finding -eq $Finding -and $_.NodeId -eq $NodeId }
            $row | Should -Not -BeNullOrEmpty
            $row.Detail | Should -Not -BeNullOrEmpty
        }

        It 'names the related subnet of an overlap' {
            ($Graph.Findings | Where-Object { $_.Finding -eq 'SubnetOverlap' -and $_.NodeId -eq '10.0.0.0/24@Azure' }).RelatedId | Should -Contain '10.0.0.0/30@Azure'
        }
    }

    It 'counts nodes, edges and findings' {
        $Graph.NodeCount | Should -Be @($Graph.Nodes).Count
        $Graph.EdgeCount | Should -Be @($Graph.Edges).Count
        $Graph.FindingCount | Should -Be @($Graph.Findings).Count
    }

    It 'warns once per type it cannot place' {
        $null = @([pscustomobject]@{ a = 1 }, [pscustomobject]@{ a = 2 }) | ConvertTo-NetworkGraph -WarningVariable warnings -WarningAction SilentlyContinue
        @($warnings).Count | Should -Be 1
        $warnings[0] | Should -Match 'skipped 2 object'
    }

    It 'builds a host-less graph from subnets alone' {
        $graph = Get-Subnet 10.0.0.0/24, 10.0.0.0/25 | ConvertTo-NetworkGraph
        $graph.Root | Should -BeNullOrEmpty
        $graph.NodeCount | Should -Be 2
        ($graph.Findings | Where-Object Finding -eq 'SubnetOverlap').Detail | Should -Be '10.0.0.0/24@None Contains 10.0.0.0/25@None.'
    }

    It 'graphs the live connections of this host' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        $graph = Get-NetworkConnection -Resolve | ConvertTo-NetworkGraph
        $graph.NodeCount | Should -BeGreaterThan 0
    }
}
