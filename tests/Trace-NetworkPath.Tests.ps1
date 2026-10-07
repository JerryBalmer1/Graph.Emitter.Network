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
            $hops[6].Ip | Should -Be '1.1.1.1'
            $hops[6].LossPercent | Should -Be 0
            $hops[0].AvgMs | Should -Be 1
            $hops[0].Responded | Should -BeTrue
        }

        It 'a hop that answered no probe while a later hop did: Responded false, LossPercent null, not 100' {
            # tracert.windows.txt hop 4: '*  *  *  Request timed out.', and hops 5 to 7 answer.
            $hop = @(ConvertHops 'ConvertFrom-NetworkGraphTracertOutput' 'tracert.windows.txt')[3]
            $hop.Hop | Should -Be 4
            $hop.Responded | Should -BeFalse
            $hop.LossPercent | Should -BeNullOrEmpty
            $hop.Ip | Should -BeNullOrEmpty
            @($hop.RttMs).Count | Should -Be 0
            $hop.AvgMs | Should -BeNullOrEmpty
        }

        It 'a hop where some probes answered keeps its real LossPercent' {
            $rows = InModuleScope NetworkGraph {
                Complete-NetworkGraphHop -Hop @(
                    [pscustomobject]@{ Hop = 1; Ip = '192.0.2.1'; Host = $null; RttMs = @(10, 14); LossPercent = 33.3 }
                    [pscustomobject]@{ Hop = 2; Ip = $null; Host = $null; RttMs = @(); LossPercent = 100 }
                    [pscustomobject]@{ Hop = 3; Ip = '192.0.2.3'; Host = $null; RttMs = @(20, 20, 20); LossPercent = 0 }
                )
            }
            $rows[0].LossPercent | Should -Be 33.3
            $rows[0].Responded | Should -BeTrue
            $rows[0].AvgMs | Should -Be 12
            $rows[1].LossPercent | Should -BeNullOrEmpty
            $rows[2].LossPercent | Should -Be 0
        }

        It 'reads Windows pathping statistics, skipping hop 0' {
            $hops = @(ConvertHops 'ConvertFrom-NetworkGraphPathpingOutput' 'pathping.windows.txt')
            $hops.Hop | Should -Be @(1, 2, 3, 4, 5, 6, 7)
            ($hops | Where-Object Hop -eq 5).Ip | Should -Be '198.51.100.2'
            # pathping reports one averaged RTT per hop: AvgMs, with no per-probe samples.
            ($hops | Where-Object Hop -eq 5).AvgMs | Should -Be 27
            @(($hops | Where-Object Hop -eq 5).RttMs).Count | Should -Be 0
            $hops.LossPercent | Select-Object -Unique | Should -Be 0
            $hops.Responded | Select-Object -Unique | Should -BeTrue
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
            # Silent to the end: no later hop answered, so these keep 100.
            $hops[1..3].LossPercent | Select-Object -Unique | Should -Be 100
            $hops[1..3].Responded | Select-Object -Unique | Should -BeFalse
        }

        It 'reads mtr --json' {
            $hops = @(ConvertHops 'ConvertFrom-NetworkGraphMtrJson' 'mtr.linux.json')
            $hops.Count | Should -Be 2
            $hops[1].Ip | Should -Be '1.1.1.1'
            # mtr reports aggregates: its average is AvgMs, RttMs has no samples.
            $hops[1].AvgMs | Should -Be 15.002
            @($hops[1].RttMs).Count | Should -Be 0
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
            $hops[0].Tool | Should -Be 'mtr'
            $hops[0].Source | Should -Be 'mtr --json -n -c 3 -m 12 1.1.1.1'
        }

        It 'runs tracert -d on Windows' {
            Mock Resolve-NetworkGraphTool -ModuleName NetworkGraph { 'tracert' }
            Set-NativeFixture -Output @{ tracert = (Get-Fixture 'tracert.windows.txt') }
            $hops = @(Trace-NetworkPath 1.1.1.1 -MaxHops 12 -Timeout 2000 -Tool Native)
            $hops.Count | Should -Be 7
            $hops[0].Source | Should -Be 'tracert -d -h 12 -w 2000 1.1.1.1'
        }
    }

    Context 'Auto on Windows' {
        BeforeAll {
            Mock Resolve-NetworkGraphTool -ModuleName NetworkGraph { 'tracert' }
            # The .NET trace is replaced, so nothing is sent; its rows are the tracert fixture's.
            $script:DotNetHops = @(ConvertHops 'ConvertFrom-NetworkGraphTracertOutput' 'tracert.windows.txt')
            Mock Get-NetworkGraphDotNetTrace -ModuleName NetworkGraph { $DotNetHops }
            Set-NativeFixture -Output @{ tracert = (Get-Fixture 'tracert.windows.txt') }
        }
        AfterAll { Clear-NativeFixture }

        It 'takes the .NET path even with tracert installed' -Skip:(-not $IsWindows) {
            $hops = @(Trace-NetworkPath 1.1.1.1 -MaxHops 12)
            $hops.Count | Should -Be 7
            $hops[0].Tool | Should -Be 'DotNet'
            Should -Invoke Get-NetworkGraphDotNetTrace -ModuleName NetworkGraph -Times 1 -Exactly
            Should -Invoke Resolve-NetworkGraphTool -ModuleName NetworkGraph -Times 0 -Exactly
        }

        It 'still runs tracert by name with -NativeTool' {
            $hops = @(Trace-NetworkPath 1.1.1.1 -MaxHops 12 -Timeout 2000 -NativeTool tracert)
            $hops[0].Tool | Should -Be 'tracert'
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
