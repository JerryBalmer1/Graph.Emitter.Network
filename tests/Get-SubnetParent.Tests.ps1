BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'Get-SubnetParent' {
    It 'finds the most specific containing prefix within the list itself' {
        $rows = @(Get-SubnetParent 10.0.1.0/24, 10.0.0.0/16, 10.0.1.128/25, 10.0.0.0/8)
        $rows.Cidr | Should -Be @('10.0.1.0/24', '10.0.0.0/16', '10.0.1.128/25', '10.0.0.0/8')
        $rows.Parent | Should -Be @('10.0.0.0/16', '10.0.0.0/8', '10.0.1.0/24', $null)
    }

    It 'places a bare address among -In candidates' {
        $row = Get-SubnetParent 10.0.1.7 -In 10.0.0.0/16, 10.0.1.0/24, 10.2.0.0/16
        $row.Cidr | Should -Be '10.0.1.7/32'
        $row.Parent | Should -Be '10.0.1.0/24'
    }

    It 'returns no parent for a prefix outside every candidate, and never itself' {
        (Get-SubnetParent 192.168.0.0/24 -In 10.0.0.0/8).Parent | Should -BeNullOrEmpty
        (Get-SubnetParent 10.0.0.0/8 -In 10.0.0.0/8).Parent | Should -BeNullOrEmpty
    }

    It 'works for IPv6' {
        (Get-SubnetParent 2001:db8:1::/64 -In 2001:db8::/32, 2001:db8:1::/48).Parent | Should -Be '2001:db8:1::/48'
    }
}
