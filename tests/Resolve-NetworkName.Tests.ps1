BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    function ConvertText([string]$Parser, [string]$Name) {
        @(InModuleScope NetworkGraph -Parameters @{ P = $Parser; T = (Get-Fixture $Name) } { param($P, $T) & $P -Text $T })
    }
}

Describe 'Resolve-NetworkName' {
    Context 'parsers (fixtures)' {
        It 'reads dig +noall +answer for A, MX, PTR and CNAME' {
            $rows = ConvertText 'ConvertFrom-NetworkGraphDigOutput' 'dig.linux.txt'
            $rows.Type | Should -Be @('A', 'A', 'MX', 'PTR', 'CNAME')
            $rows[0].Name | Should -Be 'example.com'
            $rows[0].Ttl | Should -Be 81
            $rows[2].Data | Should -Be '10 smtp.google.com'
            $rows[3].Data | Should -Be 'one.one.one.one'
            $rows[4].Data | Should -Be 'www.microsoft.com-c-3.edgekey.net'
        }

        It 'reads Windows nslookup, addresses on continuation lines' {
            $rows = ConvertText 'ConvertFrom-NetworkGraphNslookupOutput' 'nslookup.windows.txt'
            $rows.Data | Should -Be @('172.66.147.243', '104.20.23.154')
            $rows.Server | Select-Object -Unique | Should -Be 'doh.cox.net'
            $rows.Name | Select-Object -Unique | Should -Be 'example.com'
        }

        It 'reads Linux nslookup, one Address line per answer' {
            $rows = ConvertText 'ConvertFrom-NetworkGraphNslookupOutput' 'nslookup.linux.txt'
            $rows.Data | Should -Be @('104.20.23.154', '172.66.147.243')
            $rows.Server | Select-Object -Unique | Should -Be '192.168.65.7'
        }

        It 'maps Resolve-DnsName objects, answers only by default' {
            $objects = Get-FixtureJson 'Resolve-DnsName.windows.json'
            $rows = @(InModuleScope NetworkGraph -Parameters @{ O = $objects } { param($O) ConvertFrom-NetworkGraphResolveDnsName -InputObject $O })
            $rows.Type | Should -Be @('A', 'A', 'MX', 'PTR')
            $rows[2].Data | Should -Be '10 smtp.google.com'
            $rows[3].Data | Should -Be 'one.one.one.one'
            @(InModuleScope NetworkGraph -Parameters @{ O = $objects } { param($O) ConvertFrom-NetworkGraphResolveDnsName -InputObject $O -IncludeAdditional }).Count | Should -Be 13
        }
    }

    Context 'dig through the seam' {
        BeforeAll {
            Mock Resolve-NetworkGraphTool -ModuleName NetworkGraph { 'dig' }
            Set-NativeFixture -Output @{ dig = (Get-Fixture 'dig.linux.txt') }
        }
        AfterAll { Clear-NativeFixture }

        It 'passes -Type and -Server to dig and keeps the command line' {
            $rows = @(Resolve-NetworkName google.com -Type MX -Server 1.1.1.1)
            $NativeCalls[-1].ArgumentList | Should -Be @('+noall', '+answer', '@1.1.1.1', 'google.com', 'MX')
            $rows[0].Source | Should -Be 'dig +noall +answer @1.1.1.1 google.com MX'
            $rows[0].Query | Should -Be 'google.com'
            $rows[0].Server | Should -Be '1.1.1.1'
        }

        It 'asks for PTR with -x when given an address' {
            $null = Resolve-NetworkName 1.1.1.1
            $NativeCalls[-1].ArgumentList | Should -Be @('+noall', '+answer', '-x', '1.1.1.1')
        }
    }

    Context '.NET floor' {
        BeforeAll { Mock Resolve-NetworkGraphTool -ModuleName NetworkGraph { 'DotNet' } }

        It 'resolves localhost' {
            $rows = @(Resolve-NetworkName localhost)
            $rows.Data | Should -Contain '127.0.0.1'
            $rows[0].Source | Should -Be "[System.Net.Dns]::GetHostAddresses('localhost')"
        }

        It 'refuses record types it cannot ask for' {
            { Resolve-NetworkName example.com -Type MX } | Should -Throw '*-Type MX is not available with DotNet*'
        }

        It 'refuses -Server' {
            { Resolve-NetworkName example.com -Server 1.1.1.1 } | Should -Throw '*-Server needs a native resolver*'
        }
    }

    It 'resolves with the native tool' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        @(Resolve-NetworkName example.com -Tool Native).Type | Should -Contain 'A'
        # Ask 1.1.1.1 itself: some resolvers (Docker's) do not answer PTR queries.
        @(Resolve-NetworkName 1.1.1.1 -Tool Native -Server 1.1.1.1).Data | Should -Contain 'one.one.one.one'
    }
}
