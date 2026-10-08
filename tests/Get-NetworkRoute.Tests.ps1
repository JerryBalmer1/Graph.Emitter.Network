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

        It 'looks up each Get-NetRoute InterfaceIndex for InterfaceKey' {
            $keys = Get-TestKeyMap -Platform Windows
            $rows = @(InModuleScope NetworkGraph -Parameters @{ O = (Get-FixtureJson 'Get-NetRoute.windows.json'); K = $keys } { param($O, $K) ConvertFrom-NetworkGraphNetRoute -InputObject $O -KeyMap $K })
            ($rows | Where-Object Cidr -eq '0.0.0.0/0').InterfaceKey | Should -Be '{00000000-0000-0000-0000-000000000016}'
            ($rows | Where-Object Cidr -eq '127.0.0.0/8').InterfaceKey | Should -Be '{00000000-0000-0000-0000-000000000001}' -Because 'the loopback pseudo-interface has a GUID in .NET though Get-NetAdapter leaves it out'
            foreach ($row in $rows) { $row.InterfaceKey | Should -Not -BeNullOrEmpty -Because "$($row.Cidr) on $($row.Interface)" }
        }

        It 'reads ip -j route' {
            $rows = @(InModuleScope NetworkGraph -Parameters @{ T = (Get-Fixture 'ip-route.linux.json') } { param($T) ConvertFrom-NetworkGraphIpRouteJson -Text $T })
            $rows.Cidr | Should -Be @('0.0.0.0/0', '172.17.0.0/16')
            $rows[0].NextHop | Should -Be '172.17.0.1'
            $rows[1].NextHop | Should -BeNullOrEmpty
            $rows.Interface | Select-Object -Unique | Should -Be 'eth0'
            foreach ($row in $rows) { $row.InterfaceKey | Should -BeNullOrEmpty -Because 'no -KeyMap was given' }
        }

        It 'looks up each ip -j route dev for InterfaceKey' {
            $rows = @(InModuleScope NetworkGraph -Parameters @{ T = (Get-Fixture 'ip-route.linux.json'); K = (Get-TestKeyMap -Platform Linux) } { param($T, $K) ConvertFrom-NetworkGraphIpRouteJson -Text $T -KeyMap $K })
            $rows.InterfaceKey | Select-Object -Unique | Should -Be '2'
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
            $keys = Get-TestKeyMap -Platform Linux
            Mock Get-NetworkGraphInterfaceKeyMap -ModuleName NetworkGraph { $keys }.GetNewClosure()
        }
        AfterAll { Clear-NativeFixture }

        It 'names the command line and the key lookup in Source' {
            $rows = @(Get-NetworkRoute)
            $rows.Count | Should -Be 2
            $rows[0].Source | Should -Be 'ip -j route show table main; Get-Content /sys/class/net/*/ifindex'
            $rows.InterfaceKey | Select-Object -Unique | Should -Be '2'
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
