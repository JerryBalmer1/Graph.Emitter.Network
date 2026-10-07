BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'Invoke-NetworkScan' {
    It 'reads nmap -oX XML (fixture)' {
        $rows = @(InModuleScope NetworkGraph -Parameters @{ T = (Get-Fixture 'nmap.linux.xml') } { param($T) ConvertFrom-NetworkGraphNmapXml -Text $T })
        $rows.Count | Should -Be 8
        $open = $rows | Where-Object { $_.Ip -eq '127.0.0.1' -and $_.Port -eq 8080 }
        $open.Open | Should -BeTrue
        $open.Service | Should -Be 'http-proxy'
        $open.Host | Should -Be 'localhost'
        ($rows | Where-Object { $_.Ip -eq '127.0.0.1' -and $_.Port -eq 22 }).Open | Should -BeFalse
        $filtered = $rows | Where-Object { $_.Ip -eq '1.1.1.1' -and $_.Port -eq 22 }
        $filtered.State | Should -Be 'filtered'
        $filtered.Open | Should -BeNullOrEmpty
    }

    Context 'nmap through the seam' {
        BeforeAll {
            Mock Resolve-NetworkGraphTool -ModuleName NetworkGraph { 'nmap' }
            Set-NativeFixture -Output @{ nmap = (Get-Fixture 'nmap.linux.xml') }
        }
        AfterAll { Clear-NativeFixture }

        It 'runs nmap with -oX and nothing beyond -n -Pn -p, and returns Test-NetworkPort rows' {
            $rows = @(Invoke-NetworkScan 127.0.0.1, 1.1.1.1 -Port 22, 80, 443, 8080)
            $NativeCalls[-1].ArgumentList | Should -Be @('-oX', '-', '-n', '-Pn', '-p', '22,80,443,8080', '127.0.0.1', '1.1.1.1')
            $rows.Count | Should -Be 8
            $rows[0].PSObject.TypeNames[0] | Should -Be 'NetworkGraph.Port'
            $rows[0].Source | Should -Be 'nmap -oX - -n -Pn -p 22,80,443,8080 127.0.0.1 1.1.1.1'
            ($rows[0].PSObject.Properties.Name -join ',') | Should -Be 'Target,Ip,Port,Protocol,Open,Service,LatencyMs,Source'
        }
    }

    Context 'without nmap' {
        BeforeAll {
            $script:Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $Listener.Start()
            $script:OpenPort = $Listener.LocalEndpoint.Port
        }
        AfterAll { $Listener.Stop() }

        It 'connects to every target and port with TcpClient' {
            $rows = @(Invoke-NetworkScan 127.0.0.1 -Port $OpenPort -Tool DotNet)
            $rows.Open | Should -Be @($true)
            $rows[0].Source | Should -BeLike '*TcpClient*.Wait(*)  # * at a time; nmap not used'
        }

        It 'expands a CIDR target to its usable addresses' {
            $rows = @(Invoke-NetworkScan 127.0.0.0/30 -Port $OpenPort -Tool DotNet -Timeout 300)
            $rows.Ip | Should -Be @('127.0.0.1', '127.0.0.2')
        }

        It 'refuses to expand more than 4096 addresses' {
            { Invoke-NetworkScan 10.0.0.0/19 -Port 80 -Tool DotNet } | Should -Throw '*at most 4096*'
        }
    }
}
