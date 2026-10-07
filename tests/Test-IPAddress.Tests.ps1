BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:SpecialRows = @((Get-NetworkGraphData -Kind SpecialUse).Data['entries'])
    $script:CloudPrefixes = (Get-NetworkGraphData -Kind CloudRanges).Data['prefixes']
}

Describe 'Test-IPAddress' {
    It 'classifies one address in every special-use row by that row' {
        # ::ffff:0:0/96 is skipped: Test-IPAddress classifies a mapped address as the IPv4 it
        # carries (asserted below).
        $failures = foreach ($row in ($SpecialRows | Where-Object { $_['cidr'] -ne '::ffff:0:0/96' })) {
            # An address in the row that no more specific row covers: its last, first or second.
            $prefix = InModuleScope NetworkGraph -Parameters @{ Cidr = $row['cidr'] } { param($Cidr) Resolve-NetworkGraphPrefix -Cidr $Cidr }
            $candidates = @($prefix.Last, $prefix.Network, ($prefix.Network + 1)) | Where-Object { $_ -le $prefix.Last }
            $hit = $null
            foreach ($value in $candidates) {
                $ip = InModuleScope NetworkGraph -Parameters @{ V = $value; Version = $prefix.Version } { param($V, $Version) ConvertFrom-NetworkGraphIpValue -Value $V -Version $Version }
                $result = Test-IPAddress $ip
                if ($result.SpecialUse -eq $row['name'] -and $result.Source -eq $row['rfc']) { $hit = $result; break }
            }
            if (-not $hit) { "$($row['cidr']) $($row['name'])"; continue }
            $hit.Scope | Should -Be $row['scope'] -Because $row['cidr']
        }
        @($failures) | Should -BeNullOrEmpty
    }

    It 'sets the flags for <Ip>' -ForEach @(
        @{ Ip = '10.1.2.3'; Flag = 'IsPrivate'; Scope = 'Private' }
        @{ Ip = '172.31.255.255'; Flag = 'IsPrivate'; Scope = 'Private' }
        @{ Ip = '192.168.0.1'; Flag = 'IsPrivate'; Scope = 'Private' }
        @{ Ip = 'fd00::1'; Flag = 'IsPrivate'; Scope = 'Private' }
        @{ Ip = '127.0.0.1'; Flag = 'IsLoopback'; Scope = 'Loopback' }
        @{ Ip = '::1'; Flag = 'IsLoopback'; Scope = 'Loopback' }
        @{ Ip = '169.254.10.20'; Flag = 'IsLinkLocal'; Scope = 'LinkLocal' }
        @{ Ip = 'fe80::1'; Flag = 'IsLinkLocal'; Scope = 'LinkLocal' }
        @{ Ip = '100.64.0.1'; Flag = 'IsCgnat'; Scope = 'Cgnat' }
        @{ Ip = '224.0.0.251'; Flag = 'IsMulticast'; Scope = 'Multicast' }
        @{ Ip = 'ff02::1'; Flag = 'IsMulticast'; Scope = 'Multicast' }
        @{ Ip = '192.0.2.10'; Flag = 'IsDocumentation'; Scope = 'Documentation' }
        @{ Ip = '2001:db8::1'; Flag = 'IsDocumentation'; Scope = 'Documentation' }
        @{ Ip = '240.0.0.1'; Flag = 'IsReserved'; Scope = 'Reserved' }
        @{ Ip = '198.18.0.1'; Flag = 'IsReserved'; Scope = 'Benchmarking' }
        @{ Ip = '255.255.255.255'; Flag = 'IsReserved'; Scope = 'Reserved' }
    ) {
        $result = Test-IPAddress $Ip
        $result.$Flag | Should -BeTrue
        $result.Scope | Should -Be $Scope
        $result.Source | Should -Match 'RFC'
        foreach ($other in 'IsPrivate', 'IsLoopback', 'IsLinkLocal', 'IsCgnat', 'IsMulticast', 'IsDocumentation', 'IsReserved') {
            if ($other -ne $Flag) { $result.$other | Should -BeFalse -Because "$Ip is not $other" }
        }
    }

    It 'calls an ordinary address Public with no special-use source' {
        $result = Test-IPAddress 1.1.1.1
        $result.Scope | Should -Be 'Public'
        $result.Source | Should -BeNullOrEmpty
    }

    It 'classifies an IPv4-mapped IPv6 address as the IPv4 address it carries' {
        $result = Test-IPAddress ::ffff:10.0.0.1
        $result.Ip | Should -Be '10.0.0.1'
        $result.IsPrivate | Should -BeTrue
    }

    It 'finds <Cloud> for the first address of a harvested <Cloud> prefix' -ForEach @(
        @{ Cloud = 'Azure'; Asn = 8075 }
        @{ Cloud = 'AWS'; Asn = 16509 }
        @{ Cloud = 'GCP'; Asn = 15169 }
    ) {
        $key = $CloudPrefixes.Keys | Where-Object { -not $_.Contains(':') -and (@($CloudPrefixes[$_]) | Where-Object { $_[0] -eq $Cloud }) -and -not (@($CloudPrefixes[$_]) | Where-Object { $_[0] -ne $Cloud -and $_[0] -ne 'Google' }) } | Select-Object -First 1
        $key | Should -Not -BeNullOrEmpty
        $result = Test-IPAddress ($key.Split('/')[0])
        $result.Cloud | Should -Be $Cloud
        $result.Service | Should -Not -BeNullOrEmpty
        $result.Asn | Should -Be $Asn
        $result.Owner | Should -Not -BeNullOrEmpty
    }

    It 'leaves Cloud empty for private addresses' {
        (Test-IPAddress 10.0.0.1).Cloud | Should -BeNullOrEmpty
    }

    It 'takes RemoteIp from Get-NetworkConnection rows' {
        ([pscustomobject]@{ RemoteIp = '100.64.1.1' } | Test-IPAddress).IsCgnat | Should -BeTrue
    }
}
