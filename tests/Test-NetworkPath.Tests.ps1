BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    function ConvertPing([string]$Name) { InModuleScope NetworkGraph -Parameters @{ T = (Get-Fixture $Name) } { param($T) ConvertFrom-NetworkGraphPingOutput -Text $T } }
}

Describe 'Test-NetworkPath' {
    Context 'ping parser (fixtures)' {
        It 'reads Windows ping.exe replies' {
            $parsed = ConvertPing 'ping.windows.txt'
            $parsed.Ip | Should -Be '1.1.1.1'
            $parsed.Sent | Should -Be 3
            $parsed.Received | Should -Be 3
            $parsed.RttMs | Should -Be @(14, 12, 14)
        }

        It 'reads a Windows ping.exe timeout' {
            $parsed = ConvertPing 'ping-fail.windows.txt'
            $parsed.Ip | Should -Be '192.0.2.1'
            $parsed.Sent | Should -Be 2
            $parsed.Received | Should -Be 0
        }

        It 'reads Linux iputils ping replies' {
            $parsed = ConvertPing 'ping.linux.txt'
            $parsed.Ip | Should -Be '1.1.1.1'
            $parsed.Sent | Should -Be 3
            $parsed.RttMs | Should -Be @(23.3, 14.1, 13.8)
        }

        It 'reads a Linux ping with 100% loss' {
            $parsed = ConvertPing 'ping-fail.linux.txt'
            $parsed.Sent | Should -Be 2
            $parsed.Received | Should -Be 0
        }
    }

    Context 'native path through the seam' {
        BeforeAll {
            Mock Resolve-NetworkGraphTool -ModuleName NetworkGraph { 'ping' }
            $text = $IsWindows ? (Get-Fixture 'ping.windows.txt') : (Get-Fixture 'ping.linux.txt')
            Set-NativeFixture -Output @{ ping = $text }
        }
        AfterAll { Clear-NativeFixture }

        It 'returns one row with the exact command line as Source' {
            $row = Test-NetworkPath 1.1.1.1 -Count 3
            $row.Reachable | Should -BeTrue
            $row.Received | Should -Be 3
            $row.LossPercent | Should -Be 0
            $row.AverageMs | Should -BeGreaterThan 0
            $row.Source | Should -Be ($IsWindows ? 'ping -n 3 -w 1000 1.1.1.1' : 'ping -c 3 -W 1 1.1.1.1')
        }
    }

    It 'reaches loopback with the .NET floor' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        $row = Test-NetworkPath 127.0.0.1 -Count 1 -Tool DotNet
        $row.Reachable | Should -BeTrue
        $row.Source | Should -BeLike '*NetworkInformation.Ping*'
    }

    It 'reaches 1.1.1.1 with the native ping' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        (Test-NetworkPath 1.1.1.1 -Count 2 -Tool Native).Reachable | Should -BeTrue
    }
}
