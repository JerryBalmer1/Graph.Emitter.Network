BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'ConvertTo-SubnetMask' {
    It 'converts /<Length> to <Mask>' -ForEach @(
        @{ Length = 0; Mask = '0.0.0.0' }
        @{ Length = 8; Mask = '255.0.0.0' }
        @{ Length = 20; Mask = '255.255.240.0' }
        @{ Length = 26; Mask = '255.255.255.192' }
        @{ Length = 31; Mask = '255.255.255.254' }
        @{ Length = 32; Mask = '255.255.255.255' }
    ) {
        ConvertTo-SubnetMask $Length | Should -Be $Mask
    }

    It 'gives a clear error for an IPv6 prefix length' {
        { ConvertTo-SubnetMask 64 } | Should -Throw '*IPv6 has no dotted subnet mask*'
    }

    It 'takes PrefixLength from the pipeline' {
        (Get-Subnet 10.0.0.0/22 | ConvertTo-SubnetMask) | Should -Be '255.255.252.0'
    }
}
