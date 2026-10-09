BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'Get-NetworkConnection' {
    Context 'parsers (fixtures)' {
        It 'reads ss -tunap with processes and v4-mapped addresses' {
            $rows = @(InModuleScope Graph.Emitter.Network -Parameters @{ T = (Get-Fixture 'ss.linux.txt') } { param($T) ConvertFrom-NetworkGraphSsOutput -Text $T })
            $rows.Count | Should -Be 14
            $listener = $rows[0]
            "$($listener.Protocol) $($listener.LocalIp):$($listener.LocalPort) $($listener.State) $($listener.ProcessId) $($listener.ProcessName)" | Should -Be 'Tcp 0.0.0.0:8080 Listen 1264 nc'
            $listener.RemoteIp | Should -BeNullOrEmpty
            $listener.RemotePort | Should -BeNullOrEmpty
            $rows[1].RemoteIp | Should -Be '1.1.1.1'
            $rows[1].State | Should -Be 'Established'
            $rows[3].LocalIp | Should -Be '172.17.0.2'
            $rows[3].RemoteIp | Should -Be '150.171.109.151'
            $rows[3].State | Should -Be 'TimeWait'
            $rows[3].ProcessId | Should -BeNullOrEmpty
        }

        It 'maps Get-NetTCPConnection objects' {
            $rows = @(InModuleScope Graph.Emitter.Network -Parameters @{ O = (Get-FixtureJson 'Get-NetTCPConnection.windows.json') } { param($O) ConvertFrom-NetworkGraphNetTcpConnection -InputObject $O -ProcessName @{ 1660 = 'svchost' } })
            $rows.Count | Should -Be 10
            $rows[0].State | Should -Be 'Listen'
            $rows[0].RemoteIp | Should -BeNullOrEmpty
            $rows[0].ProcessName | Should -Be 'svchost'
            ($rows | Where-Object State -eq 'Established' | Select-Object -First 1).RemotePort | Should -Be 443
            ($rows | Where-Object State -eq 'Bound').RemoteIp | Should -BeNullOrEmpty
        }

        It 'maps Get-NetUDPEndpoint objects' {
            $rows = @(InModuleScope Graph.Emitter.Network -Parameters @{ O = (Get-FixtureJson 'Get-NetUDPEndpoint.windows.json') } { param($O) ConvertFrom-NetworkGraphNetUdpEndpoint -InputObject $O })
            $rows.Protocol | Select-Object -Unique | Should -Be 'Udp'
            $rows.State | Where-Object { $_ } | Should -BeNullOrEmpty
            $rows[2].LocalIp | Should -Be '::'
        }
    }

    Context 'ss through the seam' {
        BeforeAll {
            Mock Resolve-NetworkGraphTool -ModuleName Graph.Emitter.Network { 'ss' }
            Mock Resolve-NetworkGraphReverseName -ModuleName Graph.Emitter.Network { @{ '1.1.1.1' = 'one.one.one.one' } }
            Set-NativeFixture -Output @{ ss = (Get-Fixture 'ss.linux.txt') }
        }
        AfterAll { Clear-NativeFixture }

        It 'names the command line in Source on every row' {
            $rows = @(Get-NetworkConnection)
            $rows.Count | Should -Be 14
            $rows.Source | Select-Object -Unique | Should -Be 'ss -tunap'
            $rows[0].PSObject.TypeNames[0] | Should -Be 'NetworkGraph.Connection'
        }

        It 'always runs ss -tunap (ss -tnap drops the Netid column) and filters -Protocol after' {
            $rows = @(Get-NetworkConnection -Protocol Udp)
            $NativeCalls[-1].ArgumentList | Should -Be @('-tunap')
            $rows.Count | Should -Be 0
            @(Get-NetworkConnection -Protocol Tcp).Count | Should -Be 14
        }

        It 'filters by -State' {
            @(Get-NetworkConnection -State Established).RemoteIp | Should -Be @('1.1.1.1', '140.82.112.3')
        }

        It 'adds RemoteHost, Cloud, Service, Asn and Owner with -Resolve' {
            $rows = @(Get-NetworkConnection -State Established -Resolve)
            $rows[0].RemoteHost | Should -Be 'one.one.one.one'
            foreach ($name in 'RemoteHost', 'Cloud', 'Service', 'Asn', 'Owner') { $rows[0].PSObject.Properties.Name | Should -Contain $name }
        }
    }

    Context '.NET floor' {
        BeforeAll {
            $script:Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $Listener.Start()
        }
        AfterAll { $Listener.Stop() }

        It 'lists a loopback listener with no process and says so in Source' {
            $port = $Listener.LocalEndpoint.Port
            $row = Get-NetworkConnection -Tool DotNet -Protocol Tcp -State Listen | Where-Object { $_.LocalIp -eq '127.0.0.1' -and $_.LocalPort -eq $port }
            $row | Should -Not -BeNullOrEmpty
            $row.ProcessId | Should -BeNullOrEmpty
            $row.Source | Should -BeLike '*.NET floor: no process information*'
        }
    }

    It 'lists connections with the native tool, with processes' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        $rows = @(Get-NetworkConnection -Tool Native -Protocol Tcp)
        $rows.Count | Should -BeGreaterThan 0
        @($rows | Where-Object ProcessName).Count | Should -BeGreaterThan 0
    }
}
