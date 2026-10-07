BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'Get-NetworkRoute' {
    Context 'parsers (fixtures)' {
        It 'maps Get-NetRoute objects' {
            $rows = @(InModuleScope NetworkGraph -Parameters @{ O = (Get-FixtureJson 'Get-NetRoute.windows.json') } { param($O) ConvertFrom-NetworkGraphNetRoute -InputObject $O })
            $default = $rows | Where-Object Cidr -eq '0.0.0.0/0'
            "$($default.NextHop) $($default.Interface) $($default.Metric)" | Should -Be '192.168.0.1 Wi-Fi 0'
            ($rows | Where-Object Cidr -eq '192.168.0.0/24').NextHop | Should -BeNullOrEmpty
            ($rows | Where-Object Cidr -eq 'fe80::/64').Destination | Should -Be 'fe80::'
        }

        It 'reads ip -j route' {
            $rows = @(InModuleScope NetworkGraph -Parameters @{ T = (Get-Fixture 'ip-route.linux.json') } { param($T) ConvertFrom-NetworkGraphIpRouteJson -Text $T })
            $rows.Cidr | Should -Be @('0.0.0.0/0', '172.17.0.0/16')
            $rows[0].NextHop | Should -Be '172.17.0.1'
            $rows[1].NextHop | Should -BeNullOrEmpty
            $rows.Interface | Select-Object -Unique | Should -Be 'eth0'
        }

        It 'reads an empty ip -j -6 route' {
            @(InModuleScope NetworkGraph -Parameters @{ T = (Get-Fixture 'ip-route6.linux.json') } { param($T) ConvertFrom-NetworkGraphIpRouteJson -Text $T -Version 6 }).Count | Should -Be 0
        }
    }

    Context 'ip through the seam' {
        BeforeAll {
            Mock Resolve-NetworkGraphTool -ModuleName NetworkGraph { 'ip' }
            $v4 = Get-Fixture 'ip-route.linux.json'
            $v6 = Get-Fixture 'ip-route6.linux.json'
            Set-NativeFixture -Output @{ ip = { param($Arguments) ($Arguments -contains '-6') ? $v6 : $v4 }.GetNewClosure() }
        }
        AfterAll { Clear-NativeFixture }

        It 'names the command line in Source' {
            $rows = @(Get-NetworkRoute)
            $rows.Count | Should -Be 2
            $rows[0].Source | Should -Be 'ip -j route show table main'
        }

        It 'asks only for IPv4 with -AddressFamily IPv4' {
            $before = $NativeCalls.Count
            $null = Get-NetworkRoute -AddressFamily IPv4
            $calls = @($NativeCalls | Select-Object -Skip $before)
            $calls.Count | Should -Be 1
            $calls[0].ArgumentList | Should -Not -Contain '-6'
        }
    }

    It 'derives on-link routes from interface addresses on the .NET floor' {
        $rows = @(Get-NetworkRoute -Tool DotNet)
        $rows.Count | Should -BeGreaterThan 0
        $rows[0].Source | Should -BeLike '*.NET floor*'
        $rows.Metric | Where-Object { $null -ne $_ } | Should -BeNullOrEmpty
    }

    It 'reads the live route table' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        @(Get-NetworkRoute -Tool Native | Where-Object PrefixLength -eq 0).Count | Should -BeGreaterThan 0
    }
}
