BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'Get-NetworkHost' {
    Context 'firewall parsers (fixtures)' {
        It 'reads Get-NetFirewallProfile: every profile off is Disabled' {
            $result = InModuleScope NetworkGraph -Parameters @{ O = (Get-FixtureJson 'Get-NetFirewallProfile.windows.json') } { param($O) ConvertFrom-NetworkGraphNetFirewallProfile -InputObject $O }
            $result.State | Should -Be 'Disabled'
            $result.Reason | Should -Be 'Domain off, Private off, Public off'
            @($result.Profiles).Count | Should -Be 3
        }

        It 'reads a mix of profiles as Partial' {
            $mixed = @([pscustomobject]@{ Name = 'Domain'; Enabled = 'True' }, [pscustomobject]@{ Name = 'Public'; Enabled = 'False' })
            (InModuleScope NetworkGraph -Parameters @{ O = $mixed } { param($O) ConvertFrom-NetworkGraphNetFirewallProfile -InputObject $O }).State | Should -Be 'Partial'
        }

        It 'reads ufw status' {
            (InModuleScope NetworkGraph -Parameters @{ T = (Get-Fixture 'ufw.linux.txt') } { param($T) ConvertFrom-NetworkGraphUfwOutput -Text $T }).State | Should -Be 'Disabled'
            (InModuleScope NetworkGraph { ConvertFrom-NetworkGraphUfwOutput -Text 'ERROR: You need to be root to run this script' }).State | Should -Be 'Unknown'
        }

        It 'reads firewall-cmd --state that could not reach firewalld as Unknown with the reason' {
            $result = InModuleScope NetworkGraph -Parameters @{ T = (Get-Fixture 'firewall-cmd.linux.txt') } { param($T) ConvertFrom-NetworkGraphFirewallCmdOutput -Text $T }
            $result.State | Should -Be 'Unknown'
            $result.Reason | Should -BeLike 'firewalld: Error: DBUS_ERROR*'
        }
    }

    Context 'firewall: third-party products and ufw.conf' {
        BeforeAll {
            Mock Get-NetworkInterface -ModuleName NetworkGraph { @() }
            Mock Get-NetworkRoute -ModuleName NetworkGraph { @() }
            $script:Products = Get-FixtureJson 'FirewallProduct.windows.json'
        }

        It 'reads SecurityCenter2 FirewallProduct: Norton Security, productState 331776, is enabled' {
            $rows = @(InModuleScope NetworkGraph -Parameters @{ O = $Products } { param($O) ConvertFrom-NetworkGraphFirewallProduct -InputObject $O })
            $rows[0].Name | Should -Be 'Norton Security'
            $rows[0].Enabled | Should -BeTrue
            (InModuleScope NetworkGraph { ConvertFrom-NetworkGraphFirewallProduct -InputObject @([pscustomobject]@{ displayName = 'Off'; productState = 393472 }) }).Enabled | Should -BeFalse
        }

        It 'Windows: every profile off and an enabled product registered is ThirdParty, naming it' -Skip:(-not $IsWindows) {
            Mock Get-NetFirewallProfile -ModuleName NetworkGraph { Get-FixtureJson 'Get-NetFirewallProfile.windows.json' }
            Mock Get-NetworkGraphFirewallProduct -ModuleName NetworkGraph { $Products }
            $result = Get-NetworkHost
            $result.Firewall | Should -Be 'ThirdParty'
            $result.FirewallReason | Should -Be 'Windows Firewall off (Domain off, Private off, Public off); Norton Security registered and enabled in Windows Security Center'
            $result.FirewallProducts[0].Name | Should -Be 'Norton Security'
            $result.Source | Should -BeLike '*Get-NetFirewallProfile; Get-CimInstance -Namespace root/SecurityCenter2 -ClassName FirewallProduct*'
        }

        It 'Windows: every profile off and no enabled product is Disabled' -Skip:(-not $IsWindows) {
            Mock Get-NetFirewallProfile -ModuleName NetworkGraph { Get-FixtureJson 'Get-NetFirewallProfile.windows.json' }
            Mock Get-NetworkGraphFirewallProduct -ModuleName NetworkGraph { @([pscustomobject]@{ displayName = 'Off'; productState = 393472 }) }
            (Get-NetworkHost).Firewall | Should -Be 'Disabled'
        }

        It 'reads ufw.conf ENABLED=no and ENABLED=yes' {
            $text = Get-Fixture 'ufw.conf.linux.txt'
            (InModuleScope NetworkGraph -Parameters @{ T = $text } { param($T) ConvertFrom-NetworkGraphUfwConf -Text $T }).State | Should -Be 'Disabled'
            (InModuleScope NetworkGraph -Parameters @{ T = ($text -replace 'ENABLED=no', 'ENABLED=yes') } { param($T) ConvertFrom-NetworkGraphUfwConf -Text $T }).State | Should -Be 'Enabled'
            InModuleScope NetworkGraph { ConvertFrom-NetworkGraphUfwConf -Text '# no setting' } | Should -BeNullOrEmpty
        }

        It 'Linux: reads /etc/ufw/ufw.conf before ufw status, so no root is needed' {
            $conf = Join-Path $TestDrive 'ufw.conf'
            Set-Content -LiteralPath $conf -Value (Get-Fixture 'ufw.conf.linux.txt') -NoNewline
            Set-NativeFixture -Output @{ ufw = 'ERROR: You need to be root to run this script' }
            InModuleScope NetworkGraph -Parameters @{ Conf = $conf } { param($Conf) $script:NetworkGraphPlatform = 'Linux'; $script:NetworkGraphUfwConfPath = $Conf }
            try {
                $result = Get-NetworkHost
                $result.Firewall | Should -Be 'Disabled'
                $result.FirewallReason | Should -Be 'ufw.conf ENABLED=no'
                $result.Platform | Should -Be 'Linux'
                $result.Source | Should -BeLike "*Get-Content $conf*"
                $NativeCalls.Count | Should -Be 0
            }
            finally {
                Clear-NativeFixture
                InModuleScope NetworkGraph { $script:NetworkGraphPlatform = $IsWindows ? 'Windows' : ($IsLinux ? 'Linux' : 'macOS'); $script:NetworkGraphUfwConfPath = '/etc/ufw/ufw.conf' }
            }
        }
    }

    It 'summarises this host on the .NET floor' {
        $result = Get-NetworkHost -Tool DotNet
        $result.HostName | Should -Be ([System.Net.Dns]::GetHostName())
        $result.Platform | Should -BeIn 'Windows', 'Linux', 'macOS'
        @($result.Interfaces).Count | Should -BeGreaterThan 0
        $result.Firewall | Should -BeIn 'Enabled', 'Disabled', 'Partial', 'ThirdParty', 'Unknown'
        $result.FirewallReason | Should -Not -BeNullOrEmpty
        $result.Source | Should -BeLike '`[System.Net.Dns`]::GetHostName()*'
    }

    It 'summarises this host with the native tools' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        $result = Get-NetworkHost -Tool Native
        @($result.Routes).Count | Should -BeGreaterThan 0
    }
}
