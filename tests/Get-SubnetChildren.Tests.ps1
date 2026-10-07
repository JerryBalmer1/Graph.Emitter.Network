BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'Get-SubnetChildren' {
    It 'returns only direct children by default' {
        $rows = @(Get-SubnetChildren 10.0.0.0/16 -In 10.0.1.0/24, 10.0.1.128/25, 10.0.2.0/24, 10.1.0.0/24)
        $rows.Cidr | Should -Be @('10.0.1.0/24', '10.0.2.0/24')
        $rows.Parent | Select-Object -Unique | Should -Be '10.0.0.0/16'
    }

    It 'returns every descendant with its direct parent with -Recurse' {
        $rows = @(Get-SubnetChildren 10.0.0.0/16 -In 10.0.1.0/24, 10.0.1.128/25, 10.0.2.0/24 -Recurse)
        $rows.Cidr | Should -Be @('10.0.1.0/24', '10.0.2.0/24', '10.0.1.128/25')
        ($rows | Where-Object Cidr -eq '10.0.1.128/25').Parent | Should -Be '10.0.1.0/24'
    }

    It 'returns nothing when no candidate is inside' {
        @(Get-SubnetChildren 10.0.0.0/24 -In 10.0.0.0/16, 192.168.0.0/24).Count | Should -Be 0
    }

    It 'takes parents from the pipeline' {
        @('10.0.0.0/16', '10.1.0.0/16' | Get-SubnetChildren -In 10.0.5.0/24, 10.1.5.0/24).Parent | Should -Be @('10.0.0.0/16', '10.1.0.0/16')
    }
}
