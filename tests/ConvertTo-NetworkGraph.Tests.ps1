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
        Find-Node 'testhost/if/2' | Should -Not -BeNullOrEmpty
        Find-Node '172.17.0.0/16@None' | Should -Not -BeNullOrEmpty
        Find-Node '10.0.0.0/24@Azure' | Should -Not -BeNullOrEmpty
        Find-Node 'testhost/route/0.0.0.0/0/172.17.0.1/2' | Should -Not -BeNullOrEmpty
        Find-Node 'hop/1.1.1.1/tracert/4' | Should -Not -BeNullOrEmpty
        Find-Node 'testhost/conn/tcp/0.0.0.0:8080/*/1264' | Should -Not -BeNullOrEmpty
        Find-Node 'testhost:1264' | Should -Not -BeNullOrEmpty
        Find-Node '1.1.1.1' | Should -Not -BeNullOrEmpty
        Find-Node 'dns:example.com' | Should -Not -BeNullOrEmpty
        Find-Node 'cloud/Azure' | Should -Not -BeNullOrEmpty
        Find-Node 'AS8075' | Should -Not -BeNullOrEmpty
    }

    It 'keys the Interface node on InterfaceKey and keeps the alias as Name and InterfaceName' {
        $node = Find-Node 'testhost/if/2'
        "$($node.Name) $($node.InterfaceName) $($node.InterfaceKey)" | Should -Be 'eth0 eth0 2'
        Find-Node 'testhost/if/eth0' | Should -BeNullOrEmpty
        (Find-Node 'testhost/route/0.0.0.0/0/172.17.0.1/2').InterfaceKey | Should -Be '2'
    }

    It 'skips loopback interface subnets' {
        Find-Node '127.0.0.0/8@None' | Should -BeNullOrEmpty
    }

    It 'links host, interface, subnet and route with Contains and RoutesTo' {
        Test-Edge 'testhost' 'testhost/if/2' 'Contains' | Should -BeTrue
        Test-Edge '172.17.0.0/16@None' 'testhost/if/2' 'Contains' | Should -BeTrue
        Test-Edge 'testhost/if/2' 'testhost/route/0.0.0.0/0/172.17.0.1/2' 'Contains' | Should -BeTrue
        Test-Edge 'testhost/route/0.0.0.0/0/172.17.0.1/2' '172.17.0.1' 'RoutesTo' | Should -BeTrue
    }

    It 'links connections to processes and remote hosts' {
        $id = 'testhost/conn/tcp/172.17.0.2:44252/1.1.1.1:443/1265'
        Test-Edge $id 'testhost:1265' 'OwnedBy' | Should -BeTrue
        Test-Edge $id '1.1.1.1' 'ConnectsTo' | Should -BeTrue
        (Find-Node 'testhost:1265').ProcessName | Should -Be 'sleep'
    }

    It 'chains trace hops from the host' {
        Test-Edge 'testhost' 'hop/1.1.1.1/tracert/1' 'HopsTo' | Should -BeTrue
        Test-Edge 'hop/1.1.1.1/tracert/6' 'hop/1.1.1.1/tracert/7' 'HopsTo' | Should -BeTrue
        (Find-Node 'hop/1.1.1.1/tracert/4').Name | Should -Be '4 *'
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
        Test-Edge 'testhost/if/2' '172.17.0.1' 'ConnectsTo' | Should -BeTrue
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
            @{ Finding = 'WildcardListener'; NodeId = 'testhost/conn/tcp/0.0.0.0:8080/*/1264' }
            @{ Finding = 'NonCloudPublicConnection'; NodeId = 'testhost/conn/tcp/172.17.0.2:44252/1.1.1.1:443/1265' }
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

    Context 'Interface and Route Ids (stable keys)' {
        BeforeAll {
            # Windows fixtures captured together: interfaces, routes, and the key lookup.
            $script:WinInterfaces = @(InModuleScope Graph.Emitter.Network -Parameters @{ O = (Get-FixtureJson 'Get-NetIPConfiguration.windows.json') } {
                    param($O)
                    foreach ($row in ConvertFrom-NetworkGraphNetIPConfiguration -InputObject $O) { $row.PSObject.TypeNames.Insert(0, 'NetworkGraph.Interface'); $row | Add-Member Source 'Get-NetIPConfiguration -All' -PassThru }
                })
            $script:WinRoutes = @(InModuleScope Graph.Emitter.Network -Parameters @{ O = (Get-FixtureJson 'Get-NetRoute.windows.json'); K = (Get-TestKeyMap -Platform Windows) } {
                    param($O, $K)
                    foreach ($row in ConvertFrom-NetworkGraphNetRoute -InputObject $O -KeyMap $K) { $row.PSObject.TypeNames.Insert(0, 'NetworkGraph.Route'); $row | Add-Member Source "Get-NetRoute; $($K.Source)" -PassThru }
                })
            $script:WinGraph = @($WinInterfaces) + @($WinRoutes) | ConvertTo-NetworkGraph -HostName testhost
        }

        It 'Windows Interface Ids use the GUID, not the alias' {
            $wifi = $WinGraph.Nodes | Where-Object { $_.Kind -eq 'Interface' -and $_.Name -eq 'Wi-Fi' }
            $wifi.Id | Should -Be 'testhost/if/{00000000-0000-0000-0000-000000000016}'
            $wifi.InterfaceKey | Should -Be '{00000000-0000-0000-0000-000000000016}'
            foreach ($node in $WinGraph.Nodes | Where-Object Kind -eq 'Interface') { $node.Id | Should -Be "testhost/if/$($node.InterfaceKey)" -Because $node.Name }
        }

        It 'Linux Interface Ids use the ifindex, not the device name' {
            @($Graph.Nodes | Where-Object Kind -eq 'Interface' | ForEach-Object Id) | Should -Be @('testhost/if/1', 'testhost/if/2')
        }

        It 'an interface whose alias was renamed keeps its Id (same key, different alias)' {
            # The same capture with the Wi-Fi alias changed, as Rename-NetAdapter would leave it.
            $renamed = @(InModuleScope Graph.Emitter.Network -Parameters @{ O = (Get-FixtureJson 'Get-NetIPConfiguration.windows.json') } {
                    param($O)
                    foreach ($item in $O) { if ($item.InterfaceAlias -eq 'Wi-Fi') { $item.InterfaceAlias = 'Office Wireless' } }
                    foreach ($row in ConvertFrom-NetworkGraphNetIPConfiguration -InputObject $O) { $row.PSObject.TypeNames.Insert(0, 'NetworkGraph.Interface'); $row | Add-Member Source 'Get-NetIPConfiguration -All' -PassThru }
                })
            $renamedGraph = $renamed | ConvertTo-NetworkGraph -HostName testhost
            $before = $WinGraph.Nodes | Where-Object { $_.Kind -eq 'Interface' -and $_.Name -eq 'Wi-Fi' }
            $after = $renamedGraph.Nodes | Where-Object { $_.Kind -eq 'Interface' -and $_.Name -eq 'Office Wireless' }
            $after.Id | Should -Be $before.Id
            $expected = @(($WinInterfaces | ConvertTo-NetworkGraph -HostName testhost).Nodes | Where-Object Kind -eq 'Interface' | ForEach-Object Id)
            @($renamedGraph.Nodes | Where-Object Kind -eq 'Interface' | ForEach-Object Id) | Should -Be $expected
        }

        It 'Route Ids end in the InterfaceKey of the interface that contains them' {
            $routes = @($WinGraph.Nodes | Where-Object Kind -eq 'Route')
            $routes.Count | Should -Be $WinRoutes.Count
            foreach ($route in $routes) {
                $route.InterfaceKey | Should -Not -BeNullOrEmpty -Because $route.Id
                $route.Id | Should -BeLike "*/$($route.InterfaceKey)" -Because $route.Id
                $container = @($WinGraph.Edges | Where-Object { $_.Kind -ceq 'Contains' -and $_.To -eq $route.Id })
                $container.Count | Should -Be 1
                $container[0].From | Should -Be "testhost/if/$($route.InterfaceKey)"
            }
            ($WinGraph.Nodes | Where-Object Id -eq 'testhost/route/0.0.0.0/0/192.168.0.1/{00000000-0000-0000-0000-000000000016}').InterfaceName | Should -Be 'Wi-Fi'
        }

        It 'every route edge resolves to an existing Interface or RemoteHost node (<Name>)' -ForEach @(
            @{ Name = 'Windows fixtures' }
            @{ Name = 'Linux fixtures' }
        ) {
            $graph = ($Name -eq 'Windows fixtures') ? $WinGraph : $Graph
            $byId = @{}
            foreach ($node in $graph.Nodes) { $byId[$node.Id] = $node }
            $routeIds = @($graph.Nodes | Where-Object Kind -eq 'Route' | ForEach-Object Id)
            foreach ($edge in $graph.Edges | Where-Object { $_.Kind -ceq 'RoutesTo' -and $_.From -in $routeIds }) {
                $byId[$edge.To].Kind | Should -Be 'RemoteHost' -Because "$($edge.From) RoutesTo $($edge.To)"
            }
            foreach ($edge in $graph.Edges | Where-Object { $_.Kind -ceq 'Contains' -and $_.To -in $routeIds -and $byId[$_.From].Kind -ne 'Host' }) {
                $byId[$edge.From].Kind | Should -Be 'Interface' -Because "$($edge.From) Contains $($edge.To)"
            }
        }

        It 'a route row with no key borrows the key of the Interface row with the same name' {
            $route = InModuleScope Graph.Emitter.Network { New-NetworkGraphRouteRow -Cidr '192.168.0.0/24' -Interface 'Wi-Fi' }
            $route.PSObject.TypeNames.Insert(0, 'NetworkGraph.Route')
            $route | Add-Member Source 'fixture'
            $graph = @($WinInterfaces) + @($route) | ConvertTo-NetworkGraph -HostName testhost
            ($graph.Nodes | Where-Object Kind -eq 'Route').Id | Should -Be 'testhost/route/192.168.0.0/24/on-link/{00000000-0000-0000-0000-000000000016}'
        }

        It 'a row with no key and nothing to borrow from falls back to the alias' {
            $neighbor = [pscustomobject]@{ PSTypeName = 'NetworkGraph.Neighbor'; Ip = '192.0.2.10'; MacAddress = $null; Vendor = $null; State = 'Stale'; Interface = 'eth9'; Source = 'fixture' }
            $node = ($neighbor | ConvertTo-NetworkGraph -HostName testhost).Nodes | Where-Object Kind -eq 'Interface'
            $node.Id | Should -Be 'testhost/if/eth9'
            $node.InterfaceKey | Should -BeNullOrEmpty
        }
    }

    Context 'edge Source' {
        It 'every edge has a non-empty Source' {
            foreach ($edge in $Graph.Edges) { $edge.Source | Should -Not -BeNullOrEmpty -Because "$($edge.From) $($edge.Kind) $($edge.To)" }
        }

        It 'an edge takes the Source of the row that asserted it: <Name>' -ForEach @(
            @{ Name = 'Subnet Contains Interface (the interface row)'; From = '172.17.0.0/16@None'; To = 'testhost/if/2'; Kind = 'Contains'; Source = 'ip -j addr' }
            @{ Name = 'Host Contains Interface (the interface row)'; From = 'testhost'; To = 'testhost/if/2'; Kind = 'Contains'; Source = 'ip -j addr' }
            @{ Name = 'Interface Contains Route (the route row)'; From = 'testhost/if/2'; To = 'testhost/route/0.0.0.0/0/172.17.0.1/2'; Kind = 'Contains'; Source = 'ip -j route show table main; Get-Content /sys/class/net/*/ifindex' }
            @{ Name = 'Route RoutesTo next hop (the route row)'; From = 'testhost/route/0.0.0.0/0/172.17.0.1/2'; To = '172.17.0.1'; Kind = 'RoutesTo'; Source = 'ip -j route show table main; Get-Content /sys/class/net/*/ifindex' }
            @{ Name = 'Interface ConnectsTo neighbour (the neighbour row)'; From = 'testhost/if/2'; To = '172.17.0.1'; Kind = 'ConnectsTo'; Source = 'ip -j neigh; Get-Content /sys/class/net/*/ifindex' }
            @{ Name = 'Connection OwnedBy Process (the connection row)'; From = 'testhost/conn/tcp/172.17.0.2:44252/1.1.1.1:443/1265'; To = 'testhost:1265'; Kind = 'OwnedBy'; Source = 'ss -tunap' }
            @{ Name = 'Host HopsTo first hop (the hop row)'; From = 'testhost'; To = 'hop/1.1.1.1/tracert/1'; Kind = 'HopsTo'; Source = 'tracert -d -h 12 -w 2000 1.1.1.1' }
            @{ Name = 'DNS name ResolvesTo address (the DNS row)'; From = 'dns:example.com'; To = '104.20.23.154'; Kind = 'ResolvesTo'; Source = 'dig +noall +answer' }
            @{ Name = 'Host RoutesTo external address (the external address row)'; From = 'testhost'; To = '203.0.113.7'; Kind = 'RoutesTo'; Source = 'fixture' }
        ) {
            $edge = $Graph.Edges | Where-Object { $_.From -eq $From -and $_.To -eq $To -and $_.Kind -ceq $Kind }
            $edge.Source | Should -Be $Source
        }

        It 'a planned subnet''s Contains edge cites New-SubnetPlan, and BelongsTo cites Test-IPAddress when the graph classified the address' {
            ($Graph.Edges | Where-Object { $_.From -eq '10.0.0.0/22@Azure' -and $_.To -eq '10.0.0.0/24@Azure' }).Source | Should -BeLike 'Get-Subnet 10.0.0.0/24 -Cloud Azure  # planned in 10.0.0.0/22 by New-SubnetPlan*'
            # 150.171.109.151 comes from an ss row with no Cloud or Asn; the graph classified it.
            $edges = @($Graph.Edges | Where-Object { $_.From -eq '150.171.109.151' -and $_.Kind -ceq 'BelongsTo' })
            $edges.To | Should -Be @('cloud/Azure', 'AS8075')
            $edges.Source | Select-Object -Unique | Should -Be 'Test-IPAddress 150.171.109.151'
            ($Graph.Edges | Where-Object { $_.From -eq '203.0.113.7' -and $_.Kind -ceq 'BelongsTo' }).Source | Should -Be 'fixture' -Because 'the ExternalIp row carried the Asn'
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

    It 'two sockets sharing an endpoint are two Connection nodes, each owned by its process' {
        $row = {
            param($ProcessId, $Name)
            [pscustomobject]@{ PSTypeName = 'NetworkGraph.Connection'; Protocol = 'Udp'; LocalIp = '0.0.0.0'; LocalPort = 5353; RemoteIp = $null; RemotePort = $null; State = $null; ProcessId = $ProcessId; ProcessName = $Name; Source = 'Get-NetUDPEndpoint' }
        }
        $graph = @((& $row 11976 'app-one'), (& $row 52144 'app-two')) | ConvertTo-NetworkGraph -HostName testhost
        $connections = @($graph.Nodes | Where-Object Kind -eq 'Connection')
        $connections.Count | Should -Be 2
        $connections.Id | Should -Be @('testhost/conn/udp/0.0.0.0:5353/*/11976', 'testhost/conn/udp/0.0.0.0:5353/*/52144')
        @($graph.Edges | Where-Object Kind -ceq 'OwnedBy').Count | Should -Be $connections.Count
    }

    It 'a native and a .NET trace of the same target are two chains' {
        $hop = {
            param($Tool, $Number, $Ip)
            [pscustomobject]@{ PSTypeName = 'NetworkGraph.Hop'; Target = '1.1.1.1'; Tool = $Tool; Hop = $Number; Ip = $Ip; Host = $null; RttMs = @(5); AvgMs = 5; LossPercent = 0; Responded = $true; Source = "$Tool fixture" }
        }
        $graph = @((& $hop tracert 1 '192.0.2.1'), (& $hop tracert 2 '1.1.1.1'), (& $hop DotNet 1 '192.0.2.1'), (& $hop DotNet 2 '1.1.1.1')) | ConvertTo-NetworkGraph -HostName testhost
        @($graph.Nodes | Where-Object Kind -eq 'Hop').Count | Should -Be 4
        $edges = @($graph.Edges | Where-Object Kind -ceq 'HopsTo' | ForEach-Object { "$($_.From)>$($_.To)" })
        $edges | Should -Contain 'testhost>hop/1.1.1.1/tracert/1'
        $edges | Should -Contain 'hop/1.1.1.1/tracert/1>hop/1.1.1.1/tracert/2'
        $edges | Should -Contain 'testhost>hop/1.1.1.1/DotNet/1'
        $edges | Should -Contain 'hop/1.1.1.1/DotNet/1>hop/1.1.1.1/DotNet/2'
        $edges.Count | Should -Be 4
    }

    It 'graphs rows that came back from a job (Deserialized.* type names) like the direct rows' {
        # Get-NetworkConnection on the .NET floor reads this host's socket table in-process (no
        # tool, no network). The same rows go through Start-Job / Receive-Job, which deserializes them.
        $rows = @(Get-NetworkConnection -Tool DotNet -Protocol Tcp -State Listen)
        $back = @(Start-Job -ArgumentList (, $rows) -ScriptBlock { param($Rows) $Rows } | Receive-Job -Wait -AutoRemoveJob)
        $back[0].PSObject.TypeNames[0] | Should -Be 'Deserialized.NetworkGraph.Connection'
        $direct = $rows | ConvertTo-NetworkGraph -HostName testhost
        $viaJob = $back | ConvertTo-NetworkGraph -HostName testhost -WarningVariable skipped -WarningAction SilentlyContinue
        $skipped | Should -BeNullOrEmpty
        $viaJob.NodeCount | Should -Be $direct.NodeCount
        $viaJob.EdgeCount | Should -Be $direct.EdgeCount

        # And the whole fixture input, host container included.
        $fixtureRows = @(Get-TestGraphInput)
        $all = @(Start-Job -ArgumentList (, $fixtureRows) -ScriptBlock { param($Rows) $Rows } | Receive-Job -Wait -AutoRemoveJob)
        ($all | ConvertTo-NetworkGraph -WarningAction SilentlyContinue).NodeCount | Should -Be $Graph.NodeCount
    }

    It 'graphs the live connections of this host' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        $graph = Get-NetworkConnection -Resolve | ConvertTo-NetworkGraph
        $graph.NodeCount | Should -BeGreaterThan 0
    }
}
