function ConvertFrom-NetworkGraphNmapXml {
    # Not exported. 'nmap -oX -' XML to { Ip, Host, Port, Protocol, Open, State, Service } per
    # scanned port. Structured (XML), no regex. State is nmap's word; Open is $true for open,
    # $false for closed, $null for filtered, open|filtered and unfiltered. Pinned by
    # tests/fixtures/nmap.linux.xml.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    if (-not $Text.Trim()) { return }
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($Text), $settings)
    $document = [System.Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    try { $document.Load($reader) } finally { $reader.Dispose() }

    foreach ($hostNode in $document.SelectNodes('/nmaprun/host')) {
        $ip = ($hostNode.SelectSingleNode("address[@addrtype='ipv4' or @addrtype='ipv6']")).addr
        $name = ($hostNode.SelectSingleNode('hostnames/hostname')).name
        foreach ($port in $hostNode.SelectNodes('ports/port')) {
            $state = $port.SelectSingleNode('state').state
            [pscustomobject]@{
                Ip       = $ip
                Host     = $name
                Port     = [int]$port.portid
                Protocol = ($port.protocol -eq 'udp') ? 'Udp' : 'Tcp'
                Open     = switch ($state) { 'open' { $true } 'closed' { $false } default { $null } }
                State    = $state
                Service  = ($port.SelectSingleNode('service')).name
            }
        }
    }
}
