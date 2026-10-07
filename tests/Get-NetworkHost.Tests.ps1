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

    It 'summarises this host on the .NET floor' {
        $result = Get-NetworkHost -Tool DotNet
        $result.HostName | Should -Be ([System.Net.Dns]::GetHostName())
        $result.Platform | Should -BeIn 'Windows', 'Linux', 'macOS'
        @($result.Interfaces).Count | Should -BeGreaterThan 0
        $result.Firewall | Should -BeIn 'Enabled', 'Disabled', 'Partial', 'Unknown'
        $result.FirewallReason | Should -Not -BeNullOrEmpty
        $result.Source | Should -BeLike '`[System.Net.Dns`]::GetHostName()*'
    }

    It 'summarises this host with the native tools' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        $result = Get-NetworkHost -Tool Native
        @($result.Routes).Count | Should -BeGreaterThan 0
    }
}
