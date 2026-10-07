BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'ConvertFrom-SubnetMask' {
    It 'converts <Mask> to /<Length>' -ForEach @(
        @{ Mask = '0.0.0.0'; Length = 0 }
        @{ Mask = '255.0.0.0'; Length = 8 }
        @{ Mask = '255.255.240.0'; Length = 20 }
        @{ Mask = '255.255.255.192'; Length = 26 }
        @{ Mask = '255.255.255.255'; Length = 32 }
    ) {
        ConvertFrom-SubnetMask $Mask | Should -Be $Length
    }

    It 'round-trips every IPv4 length' {
        foreach ($length in 0..32) { ConvertFrom-SubnetMask (ConvertTo-SubnetMask $length) | Should -Be $length }
    }

    It 'rejects a non-contiguous mask' {
        { ConvertFrom-SubnetMask 255.0.255.0 } | Should -Throw '*not contiguous*'
    }

    It 'gives a clear error for IPv6' {
        { ConvertFrom-SubnetMask ffff:ffff:ffff:ffff:: } | Should -Throw '*IPv6 has no dotted subnet mask*'
    }

    It 'rejects text that is not an address' {
        { ConvertFrom-SubnetMask 255.255.0 } | Should -Throw '*not a dotted IPv4 mask*'
    }
}
