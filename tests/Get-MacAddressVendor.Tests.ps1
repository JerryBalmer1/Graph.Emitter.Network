BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'Get-MacAddressVendor' {
    It 'reads <Mac> in any notation' -ForEach @(
        @{ Mac = '00-15-5D-01-02-03' }
        @{ Mac = '00:15:5d:01:02:03' }
        @{ Mac = '0015.5d01.0203' }
        @{ Mac = '00155D010203' }
    ) {
        $row = Get-MacAddressVendor $Mac
        $row.MacAddress | Should -Be '00-15-5D-01-02-03'
        $row.Oui | Should -Be '00-15-5D'
        $row.Vendor | Should -Be 'Microsoft Corporation'
        $row.IsLocallyAdministered | Should -BeFalse
        $row.IsRandomized | Should -BeFalse
        $row.Source | Should -Be 'https://standards-oui.ieee.org/oui/oui.csv'
    }

    It 'gives no vendor for a locally-administered (randomised) address' {
        $row = Get-MacAddressVendor 3A-11-22-33-44-55
        $row.IsLocallyAdministered | Should -BeTrue
        $row.IsRandomized | Should -BeTrue
        $row.Vendor | Should -BeNullOrEmpty
    }

    It 'reads the multicast bit' {
        (Get-MacAddressVendor 01-00-5E-00-00-FB).IsMulticast | Should -BeTrue
        (Get-MacAddressVendor 00-15-5D-00-00-01).IsMulticast | Should -BeFalse
    }

    It 'writes an error for text that is not a MAC address and goes on' {
        $rows = @(Get-MacAddressVendor 'nope', '00-15-5D-00-00-01' -ErrorVariable problems -ErrorAction SilentlyContinue)
        $rows.Count | Should -Be 1
        $problems[0].FullyQualifiedErrorId | Should -BeLike 'InvalidMacAddress*'
    }

    It 'takes MacAddress from neighbour rows on the pipeline' {
        ([pscustomobject]@{ MacAddress = '00-15-5D-AA-BB-CC' } | Get-MacAddressVendor).Vendor | Should -Be 'Microsoft Corporation'
    }
}
