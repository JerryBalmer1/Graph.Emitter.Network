function Test-IPAddress {
    <#
    .SYNOPSIS
        Classifies an IP address: private, loopback, link-local, CGNAT, multicast, documentation,
        reserved, and the cloud and service it belongs to.

    .DESCRIPTION
        Offline. The special-use classes come from data/special-use.json (the IANA special-purpose
        registries of RFC 6890 and the RFCs that add rows, plus the multicast blocks); Source is
        the RFC of the most specific matching row and SpecialUse its registry name. Scope is that
        row's class, or Public when no row matches.

        Cloud, Service, Region, Asn and Owner come from data/cloud-ranges.json.gz (Azure Service
        Tags, AWS ip-ranges.json, Google goog.json and cloud.json): the longest published prefix
        holding the address, preferring a named service over the generic AzureCloud, AMAZON or
        Google. Asn and Owner are the cloud's primary network, not a per-prefix BGP lookup.

        IsReserved is true for the Reserved and Benchmarking scopes. An IPv4-mapped IPv6 address
        (::ffff:a.b.c.d) is classified as the IPv4 address it carries.

    .PARAMETER Address
        One or more addresses. Accepts the pipeline and objects with an Ip, RemoteIp or Address
        property.

    .EXAMPLE
        Test-IPAddress 10.1.2.3, 100.64.0.1, 20.42.65.92

    .OUTPUTS
        NetworkGraph.IPAddressInfo: Ip, Version, IsPrivate, IsLoopback, IsLinkLocal, IsCgnat,
        IsMulticast, IsDocumentation, IsReserved, Scope, SpecialUse, Source, Cloud, Service,
        Region, CloudPrefix, Asn, Owner.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.IPAddressInfo')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Ip', 'RemoteIp')]
        [string[]]
        $Address
    )

    process {
        foreach ($text in $Address) {
            $value = ConvertTo-NetworkGraphIpValue -Ip $text -Unmap
            $rows = @(Find-NetworkGraphSpecialUse -Address $value)
            $scopes = @($rows | ForEach-Object { $_['scope'] })
            $top = $rows | Select-Object -First 1
            $cloud = $null
            if (-not $top -or $top['scope'] -eq 'SpecialPurpose') {
                try { $cloud = Find-NetworkGraphCloudRange -Address $value }
                catch { Write-Verbose $_.Exception.Message }
            }

            [pscustomobject]@{
                PSTypeName      = 'NetworkGraph.IPAddressInfo'
                Ip              = $value.Ip
                Version         = $value.Version
                IsPrivate       = $scopes -contains 'Private'
                IsLoopback      = $scopes -contains 'Loopback'
                IsLinkLocal     = $scopes -contains 'LinkLocal'
                IsCgnat         = $scopes -contains 'Cgnat'
                IsMulticast     = $scopes -contains 'Multicast'
                IsDocumentation = $scopes -contains 'Documentation'
                IsReserved      = ($scopes -contains 'Reserved') -or ($scopes -contains 'Benchmarking')
                Scope           = $top ? [string]$top['scope'] : 'Public'
                SpecialUse      = $top ? [string]$top['name'] : $null
                Source          = $top ? [string]$top['rfc'] : $null
                Cloud           = $cloud ? $cloud.Cloud : $null
                Service         = $cloud ? $cloud.Service : $null
                Region          = $cloud ? $cloud.Region : $null
                CloudPrefix     = $cloud ? $cloud.Cidr : $null
                Asn             = $cloud ? $cloud.Asn : $null
                Owner           = $cloud ? $cloud.Owner : $null
            }
        }
    }
}
