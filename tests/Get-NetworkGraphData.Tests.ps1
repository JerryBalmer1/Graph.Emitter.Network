BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:DataRoot = Join-Path $ModuleRoot 'data'
}

Describe 'Get-NetworkGraphData' {
    It 'lists every kind with its location, pulled date and sources' {
        $rows = @(Get-NetworkGraphData)
        $rows.Kind | Should -Be @('CloudReservations', 'SpecialUse', 'CloudRanges', 'Oui', 'Ports', 'IpSources')
        foreach ($row in $rows) {
            $row.Location | Should -Be 'Bundled'
            $row.Pulled | Should -Match '^\d{4}-\d{2}-\d{2}$'
            $row.Entries | Should -BeGreaterThan 0
            @($row.Sources).Count | Should -BeGreaterThan 0
        }
    }

    It 'returns the parsed document with -Kind' {
        $row = Get-NetworkGraphData -Kind CloudReservations
        $row.Data['clouds'].Keys | Should -Contain 'Azure'
    }

    It 'returns source rows with -Sources' {
        $sources = @(Get-NetworkGraphData -Sources)
        @($sources | Where-Object Kind -eq 'CloudRanges').Url | Should -Contain 'https://ip-ranges.amazonaws.com/ip-ranges.json'
        @($sources | Where-Object Kind -eq 'Oui').Url | Should -Contain 'https://standards-oui.ieee.org/oui/oui.csv'
    }
}
