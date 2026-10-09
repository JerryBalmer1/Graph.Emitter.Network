function Get-NetworkGraphRdap {
    # Not exported. RDAP registration data for one address: rdap.org (which redirects to the RIR
    # holding it), else the RIR base URL from the IANA bootstrap file (RFC 9224). Returns
    # { Network, Handle, Cidr, Owner, Country, Asn, RdapUrl, Source }: RdapUrl is where the answer
    # came from after redirects, Source the request that got it, as the Invoke-WebRequest call
    # Invoke-NetworkGraphWebRequest makes. Owner is the registrant entity's
    # vCard fn, else the network name. Asn is set only when the RIR includes origin ASNs (ARIN's
    # arin_originas0 extension); RDAP itself has no BGP view.
    param(
        [Parameter(Mandatory)]
        [string]
        $Ip
    )

    $sources = (Get-NetworkGraphDataDocument -Kind IpSources)['rdap']
    $value = ConvertTo-NetworkGraphIpValue -Ip $Ip
    $response = $null
    $requested = $sources['redirector'] -replace '\{ip\}', $value.Ip
    try {
        $response = Invoke-NetworkGraphWebRequest -Uri $requested
    }
    catch {
        Write-Verbose "rdap.org failed: $($_.Exception.Message); trying the IANA bootstrap."
        $bootstrap = (Invoke-NetworkGraphWebRequest -Uri $sources['bootstrap'][[string]$value.Version]).Content | ConvertFrom-Json -AsHashtable
        $base = $null
        $bestLength = -1
        foreach ($service in @($bootstrap['services'])) {
            foreach ($cidr in @($service[0])) {
                $prefix = Resolve-NetworkGraphPrefix -Cidr $cidr
                if ($prefix.Version -eq $value.Version -and $value.Value -ge $prefix.Network -and $value.Value -le $prefix.Last -and $prefix.PrefixLength -gt $bestLength) {
                    $bestLength = $prefix.PrefixLength
                    $base = @($service[1] | Where-Object { $_ -like 'https://*' })[0]
                }
            }
        }
        if (-not $base) { throw [System.InvalidOperationException]::new("No RDAP service for $Ip in the IANA bootstrap file.") }
        $requested = $base.TrimEnd('/') + "/ip/$($value.Ip)"
        $response = Invoke-NetworkGraphWebRequest -Uri $requested
    }

    $data = $response.Content | ConvertFrom-Json -AsHashtable -Depth 64
    $owner = $null
    foreach ($entity in @($data['entities'])) {
        if (@($entity['roles']) -notcontains 'registrant') { continue }
        foreach ($field in @(@($entity['vcardArray'])[1])) {
            if (@($field)[0] -eq 'fn') { $owner = [string]@($field)[3]; break }
        }
        if ($owner) { break }
    }
    # cidr0_cidrs lists every block of the registered network; Cidr is the one that holds the
    # address (an ARIN network can span seven blocks, and the first need not contain it).
    $cidr = $null
    $blocks = @($data['cidr0_cidrs'] | Where-Object { $_ })
    foreach ($block in $blocks) {
        $prefix = Resolve-NetworkGraphPrefix -Cidr ('{0}/{1}' -f ($block['v4prefix'] ?? $block['v6prefix']), $block['length'])
        if ($prefix.Version -eq $value.Version -and $value.Value -ge $prefix.Network -and $value.Value -le $prefix.Last) { $cidr = $prefix.Cidr; break }
    }
    if ($blocks.Count -and -not $cidr) {
        Write-Warning "RDAP for $Ip lists $($blocks.Count) CIDR block(s) and none holds the address; Cidr is empty. Response: $($response.Uri)"
    }
    $asn = @($data['arin_originas0_originautnums'] | Where-Object { $_ })[0]

    [pscustomobject]@{
        Network = $data['name']
        Handle  = $data['handle']
        Cidr    = $cidr
        Owner   = $owner ? $owner : $data['name']
        Country = $data['country']
        Asn     = $asn ? [long]$asn : $null
        RdapUrl = $response.Uri
        Source  = "Invoke-WebRequest -Uri '$requested' -MaximumRedirection 5 -TimeoutSec 60"
    }
}
