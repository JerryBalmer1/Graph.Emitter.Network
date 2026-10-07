function Get-NetworkGraphRdap {
    # Not exported. RDAP registration data for one address: rdap.org (which redirects to the RIR
    # holding it), else the RIR base URL from the IANA bootstrap file (RFC 9224). Returns
    # { Network, Handle, Cidr, Owner, Country, Asn, RdapUrl }. Owner is the registrant entity's
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
    try {
        $response = Invoke-NetworkGraphWebRequest -Uri ($sources['redirector'] -replace '\{ip\}', $value.Ip)
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
        $response = Invoke-NetworkGraphWebRequest -Uri ($base.TrimEnd('/') + "/ip/$($value.Ip)")
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
    $cidr = $null
    $first = @($data['cidr0_cidrs'])[0]
    if ($first) { $cidr = '{0}/{1}' -f ($first['v4prefix'] ?? $first['v6prefix']), $first['length'] }
    $asn = @($data['arin_originas0_originautnums'] | Where-Object { $_ })[0]

    [pscustomobject]@{
        Network = $data['name']
        Handle  = $data['handle']
        Cidr    = $cidr
        Owner   = $owner ? $owner : $data['name']
        Country = $data['country']
        Asn     = $asn ? [long]$asn : $null
        RdapUrl = $response.Uri
    }
}
