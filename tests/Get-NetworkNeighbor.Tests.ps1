BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    function ConvertText([string]$Parser, [string]$Name) {
        @(InModuleScope Graph.Emitter.Network -Parameters @{ P = $Parser; T = (Get-Fixture $Name) } { param($P, $T) & $P -Text $T })
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

        It 'reads the hex index in each Windows arp -a header and looks it up for InterfaceKey' {
            # A lookup naming the three header indexes (0x8, 0xf, 0x51), so the test pins the hex
            # parse; the fixture map was captured on a later boot, when the indexes differed.
            $keys = [pscustomobject]@{ ByIndex = @{ '8' = '{k8}'; '15' = '{k15}'; '81' = '{k81}' }; ByName = @{}; Source = 'test' }
            $rows = @(InModuleScope Graph.Emitter.Network -Parameters @{ T = (Get-Fixture 'arp.windows.txt'); K = $keys } { param($T, $K) ConvertFrom-NetworkGraphArpOutput -Text $T -KeyMap $K })
            ($rows | Where-Object Ip -eq '192.168.0.1').InterfaceKey | Should -Be '{k15}'
            ($rows | Where-Object Ip -eq '172.31.131.118').InterfaceKey | Should -Be '{k81}'
            ($rows | Where-Object Interface -eq '192.168.56.1' | Select-Object -First 1).InterfaceKey | Should -Be '{k8}'
        }

        It 'reads Linux arp -a' {
            $rows = ConvertText 'ConvertFrom-NetworkGraphArpOutput' 'arp.linux.txt'
            $rows.Count | Should -Be 1
            "$($rows[0].Ip) $($rows[0].MacAddress) $($rows[0].Interface)" | Should -Be '172.17.0.1 76-7E-57-00-00-21 eth0'
            $rows = @(InModuleScope Graph.Emitter.Network -Parameters @{ T = (Get-Fixture 'arp.linux.txt'); K = (Get-TestKeyMap -Platform Linux) } { param($T, $K) ConvertFrom-NetworkGraphArpOutput -Text $T -KeyMap $K })
            $rows[0].InterfaceKey | Should -Be '2'
        }

        It 'reads ip -j neigh' {
            $rows = ConvertText 'ConvertFrom-NetworkGraphIpNeighJson' 'ip-neigh.linux.json'
            $rows[0].State | Should -Be 'Reachable'
            $rows[0].Interface | Should -Be 'eth0'
            $rows = @(InModuleScope Graph.Emitter.Network -Parameters @{ T = (Get-Fixture 'ip-neigh.linux.json'); K = (Get-TestKeyMap -Platform Linux) } { param($T, $K) ConvertFrom-NetworkGraphIpNeighJson -Text $T -KeyMap $K })
            $rows[0].InterfaceKey | Should -Be '2'
        }

        It 'reads /proc/net/arp (the Linux .NET floor)' {
            $rows = ConvertText 'ConvertFrom-NetworkGraphProcNetArp' 'proc-net-arp.linux.txt'
            "$($rows[0].Ip) $($rows[0].MacAddress) $($rows[0].State)" | Should -Be '172.17.0.1 76-7E-57-00-00-21 Complete'
            $rows = @(InModuleScope Graph.Emitter.Network -Parameters @{ T = (Get-Fixture 'proc-net-arp.linux.txt'); K = (Get-TestKeyMap -Platform Linux) } { param($T, $K) ConvertFrom-NetworkGraphProcNetArp -Text $T -KeyMap $K })
            $rows[0].InterfaceKey | Should -Be '2'
        }

        It 'maps Get-NetNeighbor objects; an all-zero MAC is no MAC' {
            $rows = @(InModuleScope Graph.Emitter.Network -Parameters @{ O = (Get-FixtureJson 'Get-NetNeighbor.windows.json') } { param($O) ConvertFrom-NetworkGraphNetNeighbor -InputObject $O })
            ($rows | Where-Object Ip -eq '255.255.255.255').State | Should -Be 'Permanent'
            $unreachable = @($rows | Where-Object State -eq 'Unreachable')
            $unreachable.Count | Should -BeGreaterThan 0
            foreach ($row in $unreachable) { $row.MacAddress | Should -BeNullOrEmpty }
        }

        It 'looks up each Get-NetNeighbor InterfaceIndex for InterfaceKey' {
            $rows = @(InModuleScope Graph.Emitter.Network -Parameters @{ O = (Get-FixtureJson 'Get-NetNeighbor.windows.json'); K = (Get-TestKeyMap -Platform Windows) } { param($O, $K) ConvertFrom-NetworkGraphNetNeighbor -InputObject $O -KeyMap $K })
            ($rows | Where-Object Ip -eq '192.168.0.1').InterfaceKey | Should -Be '{00000000-0000-0000-0000-000000000016}'
            ($rows | Where-Object Interface -eq 'OpenVPN Wintun').InterfaceKey | Should -Be '{00000000-0000-0000-0000-000000000010}'
        }
    }

    Context 'ip through the seam' {
        BeforeAll {
            Mock Resolve-NetworkGraphTool -ModuleName Graph.Emitter.Network { 'ip' }
            Set-NativeFixture -Output @{ ip = (Get-Fixture 'ip-neigh.linux.json') }
            $keys = Get-TestKeyMap -Platform Linux
            Mock Get-NetworkGraphInterfaceKeyMap -ModuleName Graph.Emitter.Network { $keys }.GetNewClosure()
        }
        AfterAll { Clear-NativeFixture }

        It 'returns rows with Vendor, State, Interface, InterfaceKey and the command lines' {
            $row = Get-NetworkNeighbor
            $row.Ip | Should -Be '172.17.0.1'
            $row.Vendor | Should -BeNullOrEmpty -Because '76-7E-57 has the locally-administered bit set'
            $row.InterfaceKey | Should -Be '2'
            $row.Source | Should -Be 'ip -j neigh; Get-Content /sys/class/net/*/ifindex'
        }
    }

    It 'has no .NET floor on Windows' -Skip:(-not $IsWindows) {
        { Get-NetworkNeighbor -Tool DotNet } | Should -Throw '*no .NET floor*'
    }

    It 'has no .NET floor on macOS, and says so instead of reading /proc' {
        InModuleScope Graph.Emitter.Network { $script:NetworkGraphPlatform = 'macOS' }
        try { { Get-NetworkNeighbor -Tool DotNet } | Should -Throw '*no .NET floor on macOS*' }
        finally { InModuleScope Graph.Emitter.Network { $script:NetworkGraphPlatform = $IsWindows ? 'Windows' : ($IsLinux ? 'Linux' : 'macOS') } }
    }

    It 'reads /proc/net/arp with -Tool DotNet on Linux' -Skip:(-not $IsLinux) {
        { Get-NetworkNeighbor -Tool DotNet -IncludeUnresolved } | Should -Not -Throw
    }

    It 'lists the live neighbour table' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        @(Get-NetworkNeighbor -Tool Native).Count | Should -BeGreaterThan 0
    }
}
