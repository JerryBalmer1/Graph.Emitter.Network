BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:DataRoot = Join-Path $ModuleRoot 'data'
    function Read-DataFile([string]$Name) {
        InModuleScope NetworkGraph -Parameters @{ Path = (Join-Path $DataRoot $Name) } { param($Path) Read-NetworkGraphDataText -Path $Path } | ConvertFrom-Json -AsHashtable -Depth 64
    }
}

Describe 'Data files' {
    It 'has the six kinds in src/NetworkGraph/data and nothing else' {
        @(Get-ChildItem $DataRoot -File).Name | Sort-Object | Should -Be @('cloud-ranges.json.gz', 'cloud-reservations.json', 'ip-sources.json', 'oui.json', 'ports.json', 'special-use.json')
    }

    It '<_> has a top-level sources array, each with a url and a pulled date' -ForEach @('cloud-ranges.json.gz', 'cloud-reservations.json', 'ip-sources.json', 'oui.json', 'ports.json', 'special-use.json') {
        $document = Read-DataFile $_
        @($document['sources']).Count | Should -BeGreaterThan 0
        foreach ($source in @($document['sources'])) {
            $source['url'] | Should -Match '^https://'
            $source['pulled'] | Should -Match '^\d{4}-\d{2}-\d{2}$'
            $source['title'] | Should -Not -BeNullOrEmpty
        }
        $document['maxAgeDays'] | Should -BeGreaterThan 0
    }

    It 'cloud reservations cite the Microsoft, AWS and Google pages' {
        $urls = @((Read-DataFile 'cloud-reservations.json')['sources'] | ForEach-Object { $_['url'] })
        $urls | Where-Object { $_ -like 'https://learn.microsoft.com/*' } | Should -Not -BeNullOrEmpty
        $urls | Where-Object { $_ -like 'https://docs.aws.amazon.com/*' } | Should -Not -BeNullOrEmpty
        $urls | Where-Object { $_ -like 'https://docs.cloud.google.com/*' } | Should -Not -BeNullOrEmpty
    }

    It 'cloud ranges keep the service or tag per prefix and the clouds'' ASNs' {
        $document = Read-DataFile 'cloud-ranges.json.gz'
        $document['prefixes'].Count | Should -BeGreaterThan 10000
        $document['clouds']['Azure']['asn'] | Should -Be 8075
        $document['clouds']['AWS']['asn'] | Should -Be 16509
        $key = @($document['prefixes'].Keys)[0]
        foreach ($row in @($document['prefixes'][$key])) { @($row).Count | Should -Be 3 -Because "$key rows are [cloud, service, region]" }
    }

    It 'special-use covers RFC 6890 and successors plus multicast, v4 and v6' {
        $cidrs = @((Read-DataFile 'special-use.json')['entries'] | ForEach-Object { $_['cidr'] })
        foreach ($cidr in '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16', '172.16.0.0/12', '192.0.2.0/24', '192.168.0.0/16', '198.18.0.0/15', '198.51.100.0/24', '203.0.113.0/24', '224.0.0.0/4', '240.0.0.0/4', '255.255.255.255/32', '::1/128', 'fc00::/7', 'fe80::/10', '2001:db8::/32', 'ff00::/8') {
            $cidrs | Should -Contain $cidr
        }
    }
}
