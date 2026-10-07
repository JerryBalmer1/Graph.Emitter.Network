BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'Test-SubnetOverlap' {
    It 'returns one row per pair with the relation read left to right' {
        $rows = @(Test-SubnetOverlap 10.0.0.0/16, 10.0.1.0/24, 10.1.0.0/16)
        $rows.Count | Should -Be 3
        "$($rows[0].Left) $($rows[0].Relation) $($rows[0].Right)" | Should -Be '10.0.0.0/16 Contains 10.0.1.0/24'
        "$($rows[1].Left) $($rows[1].Relation) $($rows[1].Right)" | Should -Be '10.0.0.0/16 Disjoint 10.1.0.0/16'
        "$($rows[2].Left) $($rows[2].Relation) $($rows[2].Right)" | Should -Be '10.0.1.0/24 Disjoint 10.1.0.0/16'
    }

    It 'reports ContainedBy and Overlaps (the same block)' {
        (Test-SubnetOverlap 10.0.1.0/24, 10.0.0.0/16).Relation | Should -Be 'ContainedBy'
        (Test-SubnetOverlap 10.0.1.0/24, 10.0.1.9/24).Relation | Should -Be 'Overlaps'
    }

    It 'finds a deliberate overlap with -OverlapOnly' {
        $rows = @(Test-SubnetOverlap 10.0.0.0/24, 10.0.1.0/24, 10.0.0.128/25, 192.168.0.0/16 -OverlapOnly)
        $rows.Count | Should -Be 1
        $rows[0].Left | Should -Be '10.0.0.0/24'
        $rows[0].Right | Should -Be '10.0.0.128/25'
    }

    It 'treats IPv4 and IPv6 as disjoint' {
        (Test-SubnetOverlap 0.0.0.0/0, ::/0).Relation | Should -Be 'Disjoint'
    }

    It 'takes Get-Subnet and New-SubnetPlan output from the pipeline' {
        $rows = @((New-SubnetPlan 10.0.0.0/24 -PrefixLength 25).Subnets + (Get-Subnet 10.0.0.64/26) | Test-SubnetOverlap -OverlapOnly)
        $rows.Count | Should -Be 1
        $rows[0].Right | Should -Be '10.0.0.64/26'
    }
}
