function ConvertFrom-NetworkGraphResolveDnsName {
    # Not exported. Resolve-DnsName objects (live, or tests/fixtures/Resolve-DnsName.windows.json)
    # to DNS rows { Name, Type, Ttl, Data, Section }. Structured. Data is the address (A, AAAA),
    # the target name (CNAME, NS, PTR), 'preference exchange' (MX), the joined strings (TXT) or
    # 'priority weight port target' (SRV). Additional-section rows are dropped unless
    # -IncludeAdditional.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $InputObject,

        [switch]
        $IncludeAdditional
    )

    foreach ($item in $InputObject) {
        $section = [string]$item.Section
        if ($section -and $section -ne 'Answer' -and -not $IncludeAdditional) { continue }
        $type = [string]$item.Type
        $data = switch ($type) {
            'A' { [string]$item.IPAddress }
            'AAAA' { [string]$item.IPAddress }
            'MX' { '{0} {1}' -f $item.Preference, $item.NameExchange }
            'TXT' { @($item.Strings) -join ' ' }
            'SRV' { '{0} {1} {2} {3}' -f $item.Priority, $item.Weight, $item.Port, $item.NameTarget }
            default { [string]$item.NameHost }
        }
        [pscustomobject]@{
            Name    = ([string]$item.Name).TrimEnd('.')
            Type    = $type
            Ttl     = ($null -ne $item.TTL) ? [int]$item.TTL : $null
            Data    = $data
            Section = $section ? $section : 'Answer'
        }
    }
}
