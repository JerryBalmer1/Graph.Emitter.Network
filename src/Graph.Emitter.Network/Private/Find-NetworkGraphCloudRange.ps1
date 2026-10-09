function Find-NetworkGraphCloudRange {
    # Not exported. The cloud-ranges.json.gz match for an address (a ConvertTo-NetworkGraphIpValue
    # result): the longest prefix that holds it, and of its rows the first whose service is not a
    # generic one (AzureCloud*, AMAZON, Google). { Cidr, Cloud, Service, Region, Asn, Owner } or
    # $null. Tries only the prefix lengths the file has, longest first.
    param(
        [Parameter(Mandatory)]
        $Address
    )

    $document = Get-NetworkGraphDataDocument -Kind CloudRanges
    $prefixes = $document['prefixes']
    $generic = @($document['genericServices'])
    foreach ($length in @($document['prefixLengths'][[string]$Address.Version])) {
        $size = [System.Numerics.BigInteger]::Pow(2, $Address.Bits - [int]$length)
        $network = $Address.Value - [System.Numerics.BigInteger]::Remainder($Address.Value, $size)
        $key = '{0}/{1}' -f (ConvertFrom-NetworkGraphIpValue -Value $network -Version $Address.Version), $length
        $rows = $prefixes[$key]
        if (-not $rows) { continue }

        $rows = @($rows)
        $best = $rows[0]
        foreach ($row in $rows) {
            $service = [string]$row[1]
            $isGeneric = $false
            foreach ($name in $generic) { if ($service -eq $name -or $service -like "$name.*") { $isGeneric = $true } }
            if (-not $isGeneric) { $best = $row; break }
        }
        $cloud = $document['clouds'][[string]$best[0]]
        return [pscustomobject]@{
            Cidr    = $key
            Cloud   = [string]$best[0]
            Service = [string]$best[1]
            Region  = $best[2]
            Asn     = $cloud ? $cloud['asn'] : $null
            Owner   = $cloud ? $cloud['owner'] : $null
        }
    }
    $null
}
