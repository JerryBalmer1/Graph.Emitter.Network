BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    function ConvertHops([string]$Parser, [string]$Name) {
        InModuleScope NetworkGraph -Parameters @{ P = $Parser; T = (Get-Fixture $Name) } { param($P, $T) & $P -Text $T }
    }
}

Describe 'Trace-NetworkPath' {
    Context 'parsers (fixtures)' {
        It 'reads Windows tracert, including a timed-out hop' {
            $hops = @(ConvertHops 'ConvertFrom-NetworkGraphTracertOutput' 'tracert.windows.txt')
            $hops.Hop | Should -Be @(1, 2, 3, 4, 5, 6, 7)
            $hops[0].Ip | Should -Be '192.168.0.1'
            $hops[0].RttMs | Should -Be @(1, 1, 1)
            $hops[3].Ip | Should -BeNullOrEmpty
            $hops[3].LossPercent | Should -Be 100
            $hops[6].Ip | Should -Be '1.1.1.1'
            $hops[6].LossPercent | Should -Be 0
        }

        It 'reads Windows pathping statistics, skipping hop 0' {
            $hops = @(ConvertHops 'ConvertFrom-NetworkGraphPathpingOutput' 'pathping.windows.txt')
            $hops.Hop | Should -Be @(1, 2, 3, 4, 5, 6, 7)
            ($hops | Where-Object Hop -eq 5).Ip | Should -Be '184.183.131.9'
            ($hops | Where-Object Hop -eq 5).RttMs | Should -Be @(27)
            $hops.LossPercent | Select-Object -Unique | Should -Be 0
        }

        It 'reads Linux traceroute -n' {
            $hops = @(ConvertHops 'ConvertFrom-NetworkGraphTracerouteOutput' 'traceroute.linux.txt')
            $hops.Count | Should -Be 2
            $hops[1].Ip | Should -Be '1.1.1.1'
            $hops[1].RttMs | Should -Be @(13.4, 13.39, 15.33)
        }

        It 'reads Linux traceroute hops that did not answer' {
            $hops = @(ConvertHops 'ConvertFrom-NetworkGraphTracerouteOutput' 'traceroute-timeout.linux.txt')
            $hops.Count | Should -Be 4
            $hops[0].Ip | Should -Be '172.17.0.1'
            @($hops[1..3].Ip | Where-Object { $_ }).Count | Should -Be 0
            $hops[1..3].LossPercent | Select-Object -Unique | Should -Be 100
        }

        It 'reads mtr --json' {
            $hops = @(ConvertHops 'ConvertFrom-NetworkGraphMtrJson' 'mtr.linux.json')
            $hops.Count | Should -Be 2
            $hops[1].Ip | Should -Be '1.1.1.1'
            $hops[1].RttMs | Should -Be @(15.002)
            $hops[1].LossPercent | Should -Be 0
        }
    }

    Context 'native path through the seam' {
        AfterAll { Clear-NativeFixture }

        It 'runs mtr with -NativeTool mtr and names the command in Source' {
            Mock Resolve-NetworkGraphTool -ModuleName NetworkGraph { 'mtr' }
            Set-NativeFixture -Output @{ mtr = (Get-Fixture 'mtr.linux.json') }
            $hops = @(Trace-NetworkPath 1.1.1.1 -NativeTool mtr -Queries 3 -MaxHops 12)
            $hops.Count | Should -Be 2
            $hops[0].Target | Should -Be '1.1.1.1'
            $hops[0].Source | Should -Be 'mtr --json -n -c 3 -m 12 1.1.1.1'
        }

        It 'runs tracert -d on Windows' {
            Mock Resolve-NetworkGraphTool -ModuleName NetworkGraph { 'tracert' }
            Set-NativeFixture -Output @{ tracert = (Get-Fixture 'tracert.windows.txt') }
            $hops = @(Trace-NetworkPath 1.1.1.1 -MaxHops 12 -Timeout 2000)
            $hops.Count | Should -Be 7
            $hops[0].Source | Should -Be 'tracert -d -h 12 -w 2000 1.1.1.1'
        }
    }

    It 'traces loopback with the .NET floor in one hop' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        $hops = @(Trace-NetworkPath 127.0.0.1 -Tool DotNet -MaxHops 3)
        $hops.Count | Should -Be 1
        $hops[0].Ip | Should -Be '127.0.0.1'
    }

    It 'traces 1.1.1.1 with the native tool and the .NET floor' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        @(Trace-NetworkPath 1.1.1.1 -Tool Native -MaxHops 20)[-1].Ip | Should -Be '1.1.1.1'
        @(Trace-NetworkPath 1.1.1.1 -Tool DotNet -MaxHops 20)[-1].Ip | Should -Be '1.1.1.1'
    }
}
