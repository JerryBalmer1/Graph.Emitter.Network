BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'Get-NetworkInterface' {
    Context 'parsers (fixtures)' {
        It 'maps Get-NetIPConfiguration (flattened) objects' {
            $rows = @(InModuleScope NetworkGraph -Parameters @{ O = (Get-FixtureJson 'Get-NetIPConfiguration.windows.json') } { param($O) ConvertFrom-NetworkGraphNetIPConfiguration -InputObject $O })
            $wifi = $rows | Where-Object Name -eq 'Wi-Fi'
            $wifi.Status | Should -Be 'Up'
            $wifi.Ip | Should -Be @('192.168.0.6')
            $wifi.PrefixLength | Should -Be @(24)
            $wifi.Gateway | Should -Be @('192.168.0.1')
            @($wifi.Dns).Count | Should -Be 3
            $wifi.MacAddress | Should -Be '04-56-E5-00-00-10'
            ($rows | Where-Object Name -eq 'Local Area Connection 3').Status | Should -Be 'Down'
        }

        It 'keys each Get-NetIPConfiguration interface on its InterfaceGuid, not its alias' {
            $rows = @(InModuleScope NetworkGraph -Parameters @{ O = (Get-FixtureJson 'Get-NetIPConfiguration.windows.json') } { param($O) ConvertFrom-NetworkGraphNetIPConfiguration -InputObject $O })
            ($rows | Where-Object Name -eq 'Wi-Fi').InterfaceKey | Should -Be '{00000000-0000-0000-0000-000000000016}'
            foreach ($row in $rows) { $row.InterfaceKey | Should -Match '^\{[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}\}$' -Because $row.Name }
            @($rows.InterfaceKey | Select-Object -Unique).Count | Should -Be $rows.Count
        }

        It 'reads ip -j addr with gateways from ip -j route and DNS from resolv.conf' {
            $rows = @(InModuleScope NetworkGraph -Parameters @{ A = (Get-Fixture 'ip-addr.linux.json'); R = (Get-Fixture 'ip-route.linux.json'); D = (Get-Fixture 'resolv.conf.linux.txt') } {
                    param($A, $R, $D) ConvertFrom-NetworkGraphIpAddrJson -Text $A -RouteText $R -ResolvConf $D })
            $rows.Name | Should -Be @('lo', 'eth0')
            $rows[0].MacAddress | Should -BeNullOrEmpty
            $rows[0].Status | Should -Be 'Up'
            $rows[0].Ip | Should -Be @('127.0.0.1', '::1')
            $rows[1].Ip | Should -Be @('172.17.0.2')
            $rows[1].PrefixLength | Should -Be @(16)
            $rows[1].Gateway | Should -Be @('172.17.0.1')
            $rows[1].Dns | Should -Be @('192.168.65.7')
            $rows.InterfaceKey | Should -Be @('1', '2') -Because 'the key is ifindex'
        }
    }

    Context 'Get-NetIPConfiguration through a mock' -Skip:(-not $IsWindows) {
        It 'names the cmdlet in Source, looks up the vendor and carries InterfaceKey' {
            Mock Resolve-NetworkGraphTool -ModuleName NetworkGraph { 'Get-NetIPConfiguration' }
            $fixture = Get-FixtureJson 'Get-NetIPConfiguration.windows.json'
            Mock Get-NetworkGraphNetIPConfiguration -ModuleName NetworkGraph { $fixture }.GetNewClosure()
            $row = Get-NetworkInterface 'Wi-*'
            $row.Vendor | Should -Be 'Intel Corporate'
            $row.InterfaceKey | Should -Be '{00000000-0000-0000-0000-000000000016}'
            @($row.PSObject.Properties.Name)[0..1] | Should -Be @('Name', 'InterfaceKey')
            $row.Source | Should -Be 'Get-NetIPConfiguration -All'
        }
    }

    It 'lists adapters on the .NET floor' {
        $rows = @(Get-NetworkInterface -Tool DotNet)
        $rows.Count | Should -BeGreaterThan 0
        $rows[0].Source | Should -BeLike '`[System.Net.NetworkInformation.NetworkInterface`]::GetAllNetworkInterfaces()*'
        if ($IsWindows) {
            foreach ($row in $rows) { $row.InterfaceKey | Should -Match '^\{[0-9A-Fa-f-]{36}\}$' -Because "$($row.Name) on Windows is keyed on its GUID" }
        }
    }

    It 'lists adapters with the native tool' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        @(Get-NetworkInterface -Tool Native | Where-Object Status -eq Up).Count | Should -BeGreaterThan 0
    }
}
