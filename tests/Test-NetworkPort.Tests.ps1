BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'Test-NetworkPort' {
    Context 'parsers (fixtures)' {
        It 'reads nc -zv results' {
            $rows = @(InModuleScope Graph.Emitter.Network -Parameters @{ T = (Get-Fixture 'nc.linux.txt') } { param($T) ConvertFrom-NetworkGraphNcOutput -Text $T })
            $rows.Count | Should -Be 2
            "$($rows[0].Ip):$($rows[0].Port) $($rows[0].Open)" | Should -Be '1.1.1.1:443 True'
            "$($rows[1].Ip):$($rows[1].Port) $($rows[1].Open)" | Should -Be '127.0.0.1:9 False'
        }

        It 'maps Test-NetConnection objects' {
            $rows = @(InModuleScope Graph.Emitter.Network -Parameters @{ O = (Get-FixtureJson 'Test-NetConnection.windows.json') } { param($O) ConvertFrom-NetworkGraphTestNetConnection -InputObject $O })
            $rows.Open | Should -Be @($true, $false)
            $rows.Port | Should -Be @(443, 9)
        }
    }

    Context 'native path through the seam' {
        BeforeAll {
            Mock Resolve-NetworkGraphTool -ModuleName Graph.Emitter.Network { 'nc' }
            Set-NativeFixture -Output @{ nc = { param($Arguments) ($Arguments[-1] -eq '443') ? 'Connection to 1.1.1.1 443 port [tcp/*] succeeded!' : 'nc: connect to 1.1.1.1 port 81 (tcp) failed: Connection refused' } }
        }
        AfterAll { Clear-NativeFixture }

        It 'returns one row per port with the IANA service and the nc command line' {
            $rows = @(Test-NetworkPort 1.1.1.1 -Port 443, 81 -Tool Native)
            $rows.Open | Should -Be @($true, $false)
            $rows[0].Service | Should -Be 'https'
            $rows[0].Protocol | Should -Be 'Tcp'
            $rows[0].Source | Should -Be 'nc -z -v -n -w 2 1.1.1.1 443'
        }
    }

    Context '.NET floor on loopback' {
        BeforeAll {
            $script:Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $Listener.Start()
            $script:OpenPort = $Listener.LocalEndpoint.Port
            $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $probe.Start(); $script:ClosedPort = $probe.LocalEndpoint.Port; $probe.Stop()
        }
        AfterAll { $Listener.Stop() }

        It 'finds the listening port open with a latency and the closed one closed' {
            $rows = @(Test-NetworkPort 127.0.0.1 -Port $OpenPort, $ClosedPort -Tool DotNet -Timeout 2000)
            $rows[0].Open | Should -BeTrue
            $rows[0].LatencyMs | Should -Not -BeNullOrEmpty
            $rows[1].Open | Should -BeFalse
            $rows[0].Source | Should -BeLike '*TcpClient*ConnectAsync*'
        }

        It 'Auto uses the .NET TcpClient path even when the native tool is installed' {
            Mock Resolve-NetworkGraphTool -ModuleName Graph.Emitter.Network { $IsWindows ? 'Test-NetConnection' : 'nc' }
            $row = Test-NetworkPort 127.0.0.1 -Port $OpenPort -Timeout 2000
            $row.Open | Should -BeTrue
            $row.Source | Should -BeLike '*TcpClient*ConnectAsync*'
            Should -Invoke Resolve-NetworkGraphTool -ModuleName Graph.Emitter.Network -Times 0 -Exactly
        }

        It 'does not report a closed UDP port open' {
            (Test-NetworkPort 127.0.0.1 -Port $ClosedPort -Protocol Udp -Tool DotNet -Timeout 500).Open | Should -Not -BeTrue
        }
    }

    It 'times each connect from its own start: a slow port 2 does not add to port 1''s LatencyMs' {
        $rows = InModuleScope Graph.Emitter.Network {
            # A fake connect: nothing is sent; port 2 takes 50 ms to start, both succeed.
            $script:NetworkGraphTcpConnector = {
                param($Client, $Address, $Port)
                if ($Port -eq 2) { Start-Sleep -Milliseconds 50 }
                [System.Threading.Tasks.Task]::CompletedTask
            }
            try {
                Test-NetworkGraphTcpPortBatch -Pair @(
                    [pscustomobject]@{ Target = 'a'; Ip = '192.0.2.1'; Port = 1 }
                    [pscustomobject]@{ Target = 'a'; Ip = '192.0.2.1'; Port = 2 }) -Timeout 2000
            }
            finally { $script:NetworkGraphTcpConnector = $null }
        }
        $rows[0].Open | Should -BeTrue
        $rows[0].LatencyMs | Should -Not -BeNullOrEmpty
        $rows[0].LatencyMs | Should -BeLessThan 20
        $rows[1].Open | Should -BeTrue
        $rows[1].LatencyMs | Should -BeGreaterOrEqual 45
    }

    It 'connects to 1.1.1.1:443 with the native tool' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        (Test-NetworkPort 1.1.1.1 -Port 443 -Tool Native).Open | Should -BeTrue
    }
}
