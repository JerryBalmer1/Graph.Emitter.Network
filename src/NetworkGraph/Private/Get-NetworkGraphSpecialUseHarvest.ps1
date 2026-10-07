function Get-NetworkGraphSpecialUseHarvest {
    # Not exported. special-use.json from the IANA IPv4 and IPv6 Special-Purpose Address Registries
    # (RFC 6890 and the RFCs that add rows), plus the two multicast blocks those registries leave
    # to the address-space registries (224.0.0.0/4, RFC 5771; ff00::/8, RFC 4291). Each row gets a
    # Scope from its registry name; rows the names do not classify are Reserved when the registry
    # marks them not globally reachable or terminated, else SpecialPurpose (Teredo, 6to4, AS112).
    param([string]$Pulled = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))

    $registries = [ordered]@{
        'https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry-1.csv' = 'IANA IPv4 Special-Purpose Address Registry'
        'https://www.iana.org/assignments/iana-ipv6-special-registry/iana-ipv6-special-registry-1.csv' = 'IANA IPv6 Special-Purpose Address Registry'
    }
    $clean = { param($text) ((([string]$text) -replace '\[\d+\]', '') -replace '\s+', ' ').Trim() }
    $scopeOf = {
        param($name, $reachable, $terminated)
        switch -Regex ($name) {
            '^Private-Use$|^Unique-Local$' { return 'Private' }
            '^Loopback' { return 'Loopback' }
            '^Link[- ]Local' { return 'LinkLocal' }
            '^Shared Address Space$' { return 'Cgnat' }
            '^Documentation' { return 'Documentation' }
            '^Benchmarking$' { return 'Benchmarking' }
        }
        ($terminated -or $reachable -eq 'False') ? 'Reserved' : 'SpecialPurpose'
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($url in $registries.Keys) {
        $rows = (Invoke-NetworkGraphWebRequest -Uri $url).Content | ConvertFrom-Csv
        foreach ($row in $rows) {
            $name = & $clean $row.Name
            $name = $name.Trim('"')
            $rfc = & $clean $row.RFC
            $reachable = & $clean $row.'Globally Reachable'
            $terminated = (& $clean $row.'Termination Date') -notin '', 'N/A'
            $rfcNumber = [regex]::Match($rfc, 'RFC\s*(\d+)').Groups[1].Value
            foreach ($block in ((& $clean $row.'Address Block') -split ',')) {
                $prefix = Resolve-NetworkGraphPrefix -Cidr $block.Trim()
                $entries.Add([ordered]@{
                        cidr              = $prefix.Cidr
                        name              = $name
                        scope             = & $scopeOf $name $reachable $terminated
                        rfc               = $rfc
                        rfcUrl            = $rfcNumber ? "https://www.rfc-editor.org/rfc/rfc$rfcNumber" : $url
                        globallyReachable = switch ($reachable) { 'True' { $true } 'False' { $false } default { $null } }
                        terminated        = $terminated
                    })
            }
        }
    }
    $entries.Add([ordered]@{ cidr = '224.0.0.0/4'; name = 'Multicast'; scope = 'Multicast'; rfc = '[RFC5771]'; rfcUrl = 'https://www.rfc-editor.org/rfc/rfc5771'; globallyReachable = $null; terminated = $false })
    $entries.Add([ordered]@{ cidr = 'ff00::/8'; name = 'Multicast'; scope = 'Multicast'; rfc = '[RFC4291], Section 2.7'; rfcUrl = 'https://www.rfc-editor.org/rfc/rfc4291#section-2.7'; globallyReachable = $null; terminated = $false })

    $sources = @(
        foreach ($url in $registries.Keys) { [ordered]@{ url = $url; title = $registries[$url]; pulled = $Pulled } }
        [ordered]@{ url = 'https://www.rfc-editor.org/rfc/rfc6890'; title = 'RFC 6890 Special-Purpose IP Address Registries'; pulled = $Pulled }
        [ordered]@{ url = 'https://www.rfc-editor.org/rfc/rfc5771'; title = 'RFC 5771 IANA Guidelines for IPv4 Multicast Address Assignments (224.0.0.0/4)'; pulled = $Pulled }
        [ordered]@{ url = 'https://www.rfc-editor.org/rfc/rfc4291#section-2.7'; title = 'RFC 4291 IP Version 6 Addressing Architecture, Multicast Addresses (ff00::/8)'; pulled = $Pulled }
    )
    [ordered]@{
        formatVersion = 1
        kind          = 'SpecialUse'
        maxAgeDays    = 365
        pulled        = $Pulled
        sources       = $sources
        entries       = $entries.ToArray()
    }
}
