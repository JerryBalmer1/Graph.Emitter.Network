BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:Answers = @{
        'https://api.ipify.org?format=json' = '{"ip":"203.0.113.7"}'
        'https://checkip.amazonaws.com'     = "203.0.113.7`n"
        'https://icanhazip.com'             = "203.0.113.7`n"
    }
}

Describe 'Get-ExternalIpAddress' {
    BeforeAll { Mock Resolve-NetworkGraphTool -ModuleName Graph.Emitter.Network { 'DotNet' } }
    AfterEach { Clear-NativeFixture }

    It 'asks every endpoint in ip-sources.json and reports agreement' {
        Set-WebFixture -Content $Answers
        $result = Get-ExternalIpAddress
        $result.Ip | Should -Be '203.0.113.7'
        $result.Agreed | Should -BeTrue
        @($result.Answers).Count | Should -Be 3
        # One command per answer row; the result's Source reruns the whole command.
        $result.Answers.Source | Should -Be @(
            "Invoke-WebRequest -Uri 'https://api.ipify.org?format=json' -MaximumRedirection 5 -TimeoutSec 10"
            "Invoke-WebRequest -Uri 'https://checkip.amazonaws.com' -MaximumRedirection 5 -TimeoutSec 10"
            "Invoke-WebRequest -Uri 'https://icanhazip.com' -MaximumRedirection 5 -TimeoutSec 10")
        $result.Source | Should -Be 'Get-ExternalIpAddress -TimeoutSec 10 -Tool DotNet'
    }

    It 'takes the majority and says the endpoints disagree' {
        $split = $Answers.Clone()
        $split['https://icanhazip.com'] = '198.51.100.1'
        Set-WebFixture -Content $split
        $result = Get-ExternalIpAddress
        $result.Ip | Should -Be '203.0.113.7'
        $result.Agreed | Should -BeFalse
    }

    It 'keeps going when one endpoint fails' {
        $some = $Answers.Clone()
        $some.Remove('https://checkip.amazonaws.com')
        Set-WebFixture -Content $some
        $result = Get-ExternalIpAddress
        $result.Ip | Should -Be '203.0.113.7'
        ($result.Answers | Where-Object Endpoint -eq 'aws-checkip').Error | Should -Match 'No fixture'
    }

    It 'fails with a fixing command when nothing answers' {
        Set-WebFixture -Content @{}
        { Get-ExternalIpAddress } | Should -Throw '*No endpoint answered*run Get-ExternalIpAddress again*'
    }

    It 'adds registration data from RDAP through rdap.org, with the CIDR block that holds the address' {
        # rdap-arin.json is MSFT's network: seven cidr0 blocks, the first 20.33.0.0/16. Ask about
        # an address in the last block (20.128.0.0/16), so the first block would be the wrong answer.
        $content = @{
            'https://api.ipify.org?format=json' = '{"ip":"20.128.0.10"}'
            'https://checkip.amazonaws.com'     = "20.128.0.10`n"
            'https://icanhazip.com'             = "20.128.0.10`n"
            'https://rdap.org/ip/20.128.0.10'   = Get-Fixture 'rdap-arin.json'
        }
        Set-WebFixture -Content $content
        $result = Get-ExternalIpAddress -Rdap
        $result.Owner | Should -Be 'Microsoft Corporation'
        $result.Network | Should -Be 'MSFT'
        $result.Cidr | Should -Be '20.128.0.0/16'
        $result.RdapUrl | Should -Be 'https://rdap.org/ip/20.128.0.10'
        $result.RdapSource | Should -Be "Invoke-WebRequest -Uri 'https://rdap.org/ip/20.128.0.10' -MaximumRedirection 5 -TimeoutSec 60"
        $result.Source | Should -Be 'Get-ExternalIpAddress -Rdap -TimeoutSec 10 -Tool DotNet'
    }

    It 'leaves Cidr empty with a warning when no RDAP block holds the address' {
        # The fixture's network does not hold 203.0.113.7 (the scrubbed address it was captured for).
        $content = $Answers.Clone()
        $content['https://rdap.org/ip/203.0.113.7'] = Get-Fixture 'rdap-arin.json'
        Set-WebFixture -Content $content
        $result = Get-ExternalIpAddress -Rdap -WarningVariable warned -WarningAction SilentlyContinue
        $result.Cidr | Should -BeNullOrEmpty
        $result.Network | Should -Be 'MSFT'
        "$warned" | Should -BeLike '*none holds the address*'
    }

    It 'falls back to the IANA bootstrap when rdap.org fails' {
        $content = $Answers.Clone()
        $content['https://data.iana.org/rdap/ipv4.json'] = Get-Fixture 'rdap-bootstrap-ipv4.json'
        $content['https://rdap.apnic.net/ip/203.0.113.7'] = Get-Fixture 'rdap-arin.json'
        Set-WebFixture -Content $content
        (Get-ExternalIpAddress -Rdap -WarningAction SilentlyContinue).RdapUrl | Should -Be 'https://rdap.apnic.net/ip/203.0.113.7'
    }

    It 'uses curl when it is the chosen tool' {
        Mock Resolve-NetworkGraphTool -ModuleName Graph.Emitter.Network { 'curl' }
        Set-NativeFixture -Output @{ curl = { param($Arguments) ($Arguments[-1] -like '*ipify*') ? '{"ip":"203.0.113.7"}' : '203.0.113.7' } }
        $result = Get-ExternalIpAddress
        $result.Ip | Should -Be '203.0.113.7'
        $result.Answers[0].Source | Should -Be 'curl -s -S --proto =https -m 10 https://api.ipify.org?format=json'
        $result.Source | Should -Be 'Get-ExternalIpAddress -TimeoutSec 10 -Tool Native'
    }

    It 'asks the real endpoints and RDAP' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        Clear-NativeFixture
        $result = Get-ExternalIpAddress -Rdap -Tool DotNet
        $result.Ip | Should -Not -BeNullOrEmpty
        $result.RdapUrl | Should -Match '^https://'
    }
}
