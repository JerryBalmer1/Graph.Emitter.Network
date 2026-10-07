BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'New-SubnetPlan' {
    It 'fits the VLSM example (250, 120, 60, 25 hosts) in a /22 with None' {
        $plan = New-SubnetPlan 10.0.0.0/22 -Hosts 250, 120, 60, 25
        $plan.Parent | Should -Be '10.0.0.0/22'
        $plan.Subnets.Cidr | Should -Be @('10.0.0.0/24', '10.0.1.0/25', '10.0.1.128/26', '10.0.1.192/27')
        $plan.Subnets.Name | Should -Be @('subnet-1', 'subnet-2', 'subnet-3', 'subnet-4')
        $plan.Subnets.Parent | Select-Object -Unique | Should -Be '10.0.0.0/22'
        $plan.Remaining | Should -Be @('10.0.1.224/27', '10.0.2.0/23')
        foreach ($subnet in $plan.Subnets) { $subnet.Usable | Should -BeGreaterOrEqual $subnet.RequestedHosts }
    }

    It 'fails the same example in a /23 with Azure and names the shortfall' {
        { New-SubnetPlan 10.0.0.0/23 -Hosts 250, 120, 60, 25 -Cloud Azure } |
            Should -Throw '*544 addresses needed*10.0.0.0/23 has 512 under Azure; short by 32 addresses*'
    }

    It 'adds the cloud reservations before rounding up (60 hosts is a /26 under None, a /25 under Azure)' {
        (New-SubnetPlan 10.0.0.0/24 -Hosts 60).Subnets[0].PrefixLength | Should -Be 26
        (New-SubnetPlan 10.0.0.0/24 -Hosts 60 -Cloud Azure).Subnets[0].PrefixLength | Should -Be 25
    }

    It 'never goes below the cloud minimum (2 hosts is a /28 under AWS)' {
        (New-SubnetPlan 10.0.0.0/24 -Hosts 2 -Cloud AWS).Subnets[0].PrefixLength | Should -Be 28
    }

    It 'places largest first whatever order the hosts are given in, keeping names' {
        $plan = New-SubnetPlan 10.0.0.0/22 -Hosts 25, 250
        $plan.Subnets.Name | Should -Be @('subnet-2', 'subnet-1')
        $plan.Subnets.Cidr | Should -Be @('10.0.0.0/24', '10.0.1.0/27')
    }

    It 'names subnets from -Requirement' {
        $plan = New-SubnetPlan 10.1.0.0/16 -Requirement ([ordered]@{ web = 200; app = 400; data = 50 }) -Cloud AWS
        $plan.Subnets.Name | Should -Be @('app', 'web', 'data')
        $plan.Subnets.Cidr | Should -Be @('10.1.0.0/23', '10.1.2.0/24', '10.1.3.0/26')
        $plan.Cloud | Should -Be 'AWS'
    }

    It 'splits equally with -PrefixLength' {
        $plan = New-SubnetPlan 10.0.0.0/24 -PrefixLength 26
        $plan.Subnets.Cidr | Should -Be @('10.0.0.0/26', '10.0.0.64/26', '10.0.0.128/26', '10.0.0.192/26')
        @($plan.Remaining).Count | Should -Be 0
    }

    It 'rejects an equal split shorter than the parent' {
        { New-SubnetPlan 10.0.0.0/24 -PrefixLength 23 } | Should -Throw '*between 24 and 32*'
    }

    It 'plans IPv6' {
        (New-SubnetPlan 2001:db8::/48 -PrefixLength 50).Subnets.Cidr | Should -Be @('2001:db8::/50', '2001:db8:0:4000::/50', '2001:db8:0:8000::/50', '2001:db8:0:c000::/50')
    }

    It 'returns subnets that are NetworkGraph.Subnet as well as PlannedSubnet' {
        $subnet = (New-SubnetPlan 10.0.0.0/24 -Hosts 10).Subnets[0]
        $subnet.PSObject.TypeNames | Should -Contain 'NetworkGraph.PlannedSubnet'
        $subnet.PSObject.TypeNames | Should -Contain 'NetworkGraph.Subnet'
    }
}
