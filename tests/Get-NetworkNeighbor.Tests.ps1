BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    function ConvertText([string]$Parser, [string]$Name) {
        @(InModuleScope NetworkGraph -Parameters @{ P = $Parser; T = (Get-Fixture $Name) } { param($P, $T) & $P -Text $T })
    }
}

Describe 'Get-NetworkNeighbor' {
    Context 'parsers (fixtures)' {
        It 'reads Windows arp -a, with the interface from each header' {
            $rows = ConvertText 'ConvertFrom-NetworkGraphArpOutput' 'arp.windows.txt'
            $rows.Count | Should -Be 31
            $row = $rows | Where-Object Ip -eq '192.168.0.1'
            $row.MacAddress | Should -Be 'CC-40-D0-00-00-02'
            $row.State | Should -Be 'Dynamic'
            $row.Interface | Should -Be '192.168.0.6'
            ($rows | Where-Object Ip -eq '172.31.131.118').Interface | Should -Be '172.31.128.1'
        }

        It 'reads Linux arp -a' {
            $rows = ConvertText 'ConvertFrom-NetworkGraphArpOutput' 'arp.linux.txt'
            $rows.Count | Should -Be 1
            "$($rows[0].Ip) $($rows[0].MacAddress) $($rows[0].Interface)" | Should -Be '172.17.0.1 76-7E-57-00-00-21 eth0'
        }

        It 'reads ip -j neigh' {
            $rows = ConvertText 'ConvertFrom-NetworkGraphIpNeighJson' 'ip-neigh.linux.json'
            $rows[0].State | Should -Be 'Reachable'
            $rows[0].Interface | Should -Be 'eth0'
        }

        It 'reads /proc/net/arp (the Linux .NET floor)' {
            $rows = ConvertText 'ConvertFrom-NetworkGraphProcNetArp' 'proc-net-arp.linux.txt'
            "$($rows[0].Ip) $($rows[0].MacAddress) $($rows[0].State)" | Should -Be '172.17.0.1 76-7E-57-00-00-21 Complete'
        }

        It 'maps Get-NetNeighbor objects; an all-zero MAC is no MAC' {
            $rows = @(InModuleScope NetworkGraph -Parameters @{ O = (Get-FixtureJson 'Get-NetNeighbor.windows.json') } { param($O) ConvertFrom-NetworkGraphNetNeighbor -InputObject $O })
            ($rows | Where-Object Ip -eq '255.255.255.255').State | Should -Be 'Permanent'
            ($rows | Where-Object State -eq 'Unreachable').MacAddress | Should -BeNullOrEmpty
        }
    }

    Context 'ip through the seam' {
        BeforeAll {
            Mock Resolve-NetworkGraphTool -ModuleName NetworkGraph { 'ip' }
            Set-NativeFixture -Output @{ ip = (Get-Fixture 'ip-neigh.linux.json') }
        }
        AfterAll { Clear-NativeFixture }

        It 'returns rows with Vendor, State, Interface and the command line' {
            $row = Get-NetworkNeighbor
            $row.Ip | Should -Be '172.17.0.1'
            $row.Vendor | Should -BeNullOrEmpty -Because '76-7E-57 has the locally-administered bit set'
            $row.Source | Should -Be 'ip -j neigh'
        }
    }

    It 'has no .NET floor on Windows' -Skip:(-not $IsWindows) {
        { Get-NetworkNeighbor -Tool DotNet } | Should -Throw '*no .NET floor*'
    }

    It 'reads /proc/net/arp with -Tool DotNet on Linux' -Skip:(-not $IsLinux) {
        { Get-NetworkNeighbor -Tool DotNet -IncludeUnresolved } | Should -Not -Throw
    }

    It 'lists the live neighbour table' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        @(Get-NetworkNeighbor -Tool Native).Count | Should -BeGreaterThan 0
    }
}
