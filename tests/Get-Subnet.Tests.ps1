BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'Get-Subnet' {
    Context 'IPv4 known answers' {
        It '<Cidr> has <Usable> usable from <First> to <Last>' -ForEach @(
            @{ Cidr = '10.0.0.0/8'; Usable = 16777214; First = '10.0.0.1'; Last = '10.255.255.254'; Broadcast = '10.255.255.255'; Mask = '255.0.0.0'; Wildcard = '0.255.255.255' }
            @{ Cidr = '172.16.0.0/16'; Usable = 65534; First = '172.16.0.1'; Last = '172.16.255.254'; Broadcast = '172.16.255.255'; Mask = '255.255.0.0'; Wildcard = '0.0.255.255' }
            @{ Cidr = '192.168.1.0/24'; Usable = 254; First = '192.168.1.1'; Last = '192.168.1.254'; Broadcast = '192.168.1.255'; Mask = '255.255.255.0'; Wildcard = '0.0.0.255' }
            @{ Cidr = '192.168.1.128/25'; Usable = 126; First = '192.168.1.129'; Last = '192.168.1.254'; Broadcast = '192.168.1.255'; Mask = '255.255.255.128'; Wildcard = '0.0.0.127' }
            @{ Cidr = '192.168.1.4/30'; Usable = 2; First = '192.168.1.5'; Last = '192.168.1.6'; Broadcast = '192.168.1.7'; Mask = '255.255.255.252'; Wildcard = '0.0.0.3' }
            @{ Cidr = '192.168.1.6/31'; Usable = 2; First = '192.168.1.6'; Last = '192.168.1.7'; Broadcast = $null; Mask = '255.255.255.254'; Wildcard = '0.0.0.1' }
            @{ Cidr = '192.168.1.9/32'; Usable = 1; First = '192.168.1.9'; Last = '192.168.1.9'; Broadcast = $null; Mask = '255.255.255.255'; Wildcard = '0.0.0.0' }
        ) {
            $subnet = Get-Subnet $Cidr
            $subnet.Cidr | Should -Be $Cidr
            $subnet.Version | Should -Be 4
            $subnet.Usable | Should -Be $Usable
            $subnet.FirstUsable | Should -Be $First
            $subnet.LastUsable | Should -Be $Last
            $subnet.Broadcast | Should -Be $Broadcast
            $subnet.Mask | Should -Be $Mask
            $subnet.Wildcard | Should -Be $Wildcard
            $subnet.Cloud | Should -Be 'None'
        }

        It 'treats a /31 as a point-to-point link with no reserved addresses (RFC 3021)' {
            @((Get-Subnet 10.0.0.0/31).Reserved).Count | Should -Be 0
        }

        It 'clears host bits: 10.0.0.77/26 is 10.0.0.64/26' {
            (Get-Subnet 10.0.0.77/26).Cidr | Should -Be '10.0.0.64/26'
        }

        It 'takes -Address with -PrefixLength or -Mask' {
            (Get-Subnet -Address 192.168.1.77 -PrefixLength 26).Cidr | Should -Be '192.168.1.64/26'
            (Get-Subnet -Address 192.168.1.77 -Mask 255.255.255.192).Usable | Should -Be 62
        }

        It 'takes the pipeline, by value and by Cidr property' {
            @('10.0.0.0/24', '10.0.1.0/25' | Get-Subnet).Usable | Should -Be @(254, 126)
            ([pscustomobject]@{ Cidr = '10.9.0.0/16' } | Get-Subnet).Usable | Should -Be 65534
        }

        It 'rejects text that is not a prefix' {
            { Get-Subnet 10.0.0/24 } | Should -Throw '*not an IPv4 address*'
            { Get-Subnet 10.0.0.0/33 } | Should -Throw '*out of range*'
        }
    }

    Context 'IPv6 known answers' {
        It '<Cidr> has <Usable> addresses' -ForEach @(
            @{ Cidr = '2001:db8:abcd::/48'; Usable = '1208925819614629174706176'; First = '2001:db8:abcd::'; Last = '2001:db8:abcd:ffff:ffff:ffff:ffff:ffff' }
            @{ Cidr = '2001:db8::/64'; Usable = '18446744073709551616'; First = '2001:db8::'; Last = '2001:db8::ffff:ffff:ffff:ffff' }
            @{ Cidr = '2001:db8::/127'; Usable = '2'; First = '2001:db8::'; Last = '2001:db8::1' }
            @{ Cidr = '2001:db8::5/128'; Usable = '1'; First = '2001:db8::5'; Last = '2001:db8::5' }
        ) {
            $subnet = Get-Subnet $Cidr
            $subnet.Version | Should -Be 6
            $subnet.Usable.ToString() | Should -Be $Usable
            $subnet.FirstUsable | Should -Be $First
            $subnet.LastUsable | Should -Be $Last
            $subnet.Broadcast | Should -BeNullOrEmpty
        }
    }

    Context '200 random IPv4 prefixes' {
        It 'puts Network lowest, Broadcast highest and a consistent usable count' {
            $random = [System.Random]::new(20261007)
            for ($i = 0; $i -lt 200; $i++) {
                $value = [uint32]$random.NextInt64(0, 4294967296)
                $length = $random.Next(0, 33)
                # Independent of the module: IPAddress.Parse reads a decimal number as an IPv4 address.
                $toIp = { param([uint64]$v) [System.Net.IPAddress]::Parse("$v").ToString() }
                $ip = & $toIp $value
                $size = [uint64][math]::Pow(2, 32 - $length)
                $network = [uint64]$value - ([uint64]$value % $size)
                $last = $network + $size - 1

                $subnet = Get-Subnet -Address $ip -PrefixLength $length
                $subnet.Network | Should -Be (& $toIp $network) -Because "$ip/$length network"
                if ($length -le 30) {
                    $subnet.Broadcast | Should -Be (& $toIp $last) -Because "$ip/$length broadcast"
                    $subnet.Usable | Should -Be ($size - 2) -Because "$ip/$length usable"
                    $subnet.FirstUsable | Should -Be (& $toIp ($network + 1))
                    $subnet.LastUsable | Should -Be (& $toIp ($last - 1))
                }
                else {
                    $subnet.Broadcast | Should -BeNullOrEmpty
                    $subnet.Usable | Should -Be $size
                }
            }
        }
    }

    Context 'Cloud reservations' {
        It '<Cloud> /24 has <Usable> usable and <Reserved> reserved rows' -ForEach @(
            @{ Cloud = 'Azure'; Usable = 251; Reserved = 5; First = '10.0.0.4'; Last = '10.0.0.254'; Gateway = '10.0.0.1' }
            @{ Cloud = 'AWS'; Usable = 251; Reserved = 5; First = '10.0.0.4'; Last = '10.0.0.254'; Gateway = '10.0.0.1' }
            @{ Cloud = 'GCP'; Usable = 252; Reserved = 4; First = '10.0.0.2'; Last = '10.0.0.253'; Gateway = '10.0.0.1' }
            @{ Cloud = 'None'; Usable = 254; Reserved = 2; First = '10.0.0.1'; Last = '10.0.0.254'; Gateway = $null }
        ) {
            $subnet = Get-Subnet 10.0.0.0/24 -Cloud $Cloud
            $subnet.Usable | Should -Be $Usable
            @($subnet.Reserved).Count | Should -Be $Reserved
            $subnet.FirstUsable | Should -Be $First
            $subnet.LastUsable | Should -Be $Last
            $subnet.Gateway | Should -Be $Gateway
            $subnet.BelowCloudMinimum | Should -BeFalse
            foreach ($row in $subnet.Reserved) { $row.Source | Should -Match '^https://' }
        }

        It 'Azure /24 reserves .0, .1, .2, .3 and .255 with their roles' {
            $rows = (Get-Subnet 10.0.0.0/24 -Cloud Azure).Reserved
            $rows.Ip | Should -Be @('10.0.0.0', '10.0.0.1', '10.0.0.2', '10.0.0.3', '10.0.0.255')
            $rows.Role | Should -Be @('Network address', 'Default gateway', 'Azure DNS mapping', 'Azure DNS mapping', 'Broadcast address')
        }

        It 'GCP reserves the second-to-last address' {
            (Get-Subnet 10.0.0.0/24 -Cloud GCP).Reserved.Ip | Should -Contain '10.0.0.254'
        }

        It '<Cloud> at its minimum /<Length> has <Usable> usable' -ForEach @(
            @{ Cloud = 'Azure'; Length = 29; Usable = 3 }
            @{ Cloud = 'AWS'; Length = 28; Usable = 11 }
            @{ Cloud = 'GCP'; Length = 29; Usable = 4 }
            @{ Cloud = 'None'; Length = 30; Usable = 2 }
        ) {
            $subnet = Get-Subnet "10.0.0.0/$Length" -Cloud $Cloud
            $subnet.Usable | Should -Be $Usable
            $subnet.BelowCloudMinimum | Should -BeFalse
        }

        It 'flags a subnet below the cloud minimum and warns' {
            $subnet = Get-Subnet 10.0.0.0/30 -Cloud Azure -WarningVariable warnings -WarningAction SilentlyContinue
            $subnet.BelowCloudMinimum | Should -BeTrue
            $subnet.Usable | Should -Be 0
            $warnings | Should -Match 'smaller than the Azure minimum subnet /29'
            (Get-Subnet 10.0.0.0/29 -Cloud AWS -WarningAction SilentlyContinue).BelowCloudMinimum | Should -BeTrue
        }

        It 'applies the AWS reservations to IPv6 and warns that Azure has none documented' {
            (Get-Subnet 2001:db8::/64 -Cloud AWS).Reserved.Ip | Should -Be @('2001:db8::', '2001:db8::1', '2001:db8::2', '2001:db8::3', '2001:db8::ffff:ffff:ffff:ffff')
            $subnet = Get-Subnet 2001:db8::/64 -Cloud Azure -WarningVariable warnings -WarningAction SilentlyContinue
            @($subnet.Reserved).Count | Should -Be 0
            $warnings | Should -Match 'no IPv6 subnet reservations'
        }
    }
}
