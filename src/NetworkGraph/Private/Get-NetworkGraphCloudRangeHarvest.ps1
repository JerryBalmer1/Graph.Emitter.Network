function Get-NetworkGraphCloudRangeHarvest {
    # Not exported. cloud-ranges.json.gz from the three public range files: Azure Service Tags
    # (Public cloud; the weekly file's URL is read from its download page), AWS ip-ranges.json, and
    # Google goog.json (all Google, cloud Google) plus cloud.json (Google Cloud customer ranges,
    # cloud GCP). prefixes maps each canonical prefix to [cloud, service, region] rows; the
    # service or tag name is kept per prefix. prefixLengths lists, per IP version, the lengths
    # present, longest first, so a lookup tries only those.
    param([string]$Pulled = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))

    $azurePage = 'https://www.microsoft.com/en-us/download/details.aspx?id=56519'
    $awsUrl = 'https://ip-ranges.amazonaws.com/ip-ranges.json'
    $googUrl = 'https://www.gstatic.com/ipranges/goog.json'
    $gcpUrl = 'https://www.gstatic.com/ipranges/cloud.json'

    $page = (Invoke-NetworkGraphWebRequest -Uri $azurePage).Content
    $azureUrl = [regex]::Match($page, 'https://download\.microsoft\.com/[^"''\s<>]+/ServiceTags_Public_\d+\.json').Value
    if (-not $azureUrl) { throw [System.InvalidOperationException]::new("No ServiceTags_Public_*.json link on $azurePage; the page layout changed. Read the page and update Get-NetworkGraphCloudRangeHarvest.") }

    $prefixes = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $lengths = @{ '4' = [System.Collections.Generic.HashSet[int]]::new(); '6' = [System.Collections.Generic.HashSet[int]]::new() }
    $add = {
        param([string]$Cidr, [string]$Cloud, [string]$Service, [string]$Region)
        $parts = $Cidr.Trim().Split('/')
        $ip = [System.Net.IPAddress]::Parse($parts[0])
        $canonical = '{0}/{1}' -f $ip.ToString(), [int]$parts[1]
        if (-not $seen.Add("$canonical|$Cloud|$Service|$Region")) { return }
        $list = $null
        if (-not $prefixes.TryGetValue($canonical, [ref]$list)) {
            $list = [System.Collections.Generic.List[object]]::new()
            $prefixes[$canonical] = $list
            $null = $lengths[($ip.AddressFamily -eq 'InterNetwork') ? '4' : '6'].Add([int]$parts[1])
        }
        $list.Add(@($Cloud, $Service, ($Region ? $Region : $null)))
    }

    $azure = (Invoke-NetworkGraphWebRequest -Uri $azureUrl).Content | ConvertFrom-Json
    foreach ($tag in $azure.values) {
        foreach ($cidr in $tag.properties.addressPrefixes) { & $add $cidr 'Azure' $tag.name $tag.properties.region }
    }
    $aws = (Invoke-NetworkGraphWebRequest -Uri $awsUrl).Content | ConvertFrom-Json
    foreach ($item in $aws.prefixes) { & $add $item.ip_prefix 'AWS' $item.service $item.region }
    foreach ($item in $aws.ipv6_prefixes) { & $add $item.ipv6_prefix 'AWS' $item.service $item.region }
    $gcp = (Invoke-NetworkGraphWebRequest -Uri $gcpUrl).Content | ConvertFrom-Json
    foreach ($item in $gcp.prefixes) { & $add ($item.ipv4Prefix ?? $item.ipv6Prefix) 'GCP' $item.service $item.scope }
    $goog = (Invoke-NetworkGraphWebRequest -Uri $googUrl).Content | ConvertFrom-Json
    foreach ($item in $goog.prefixes) { & $add ($item.ipv4Prefix ?? $item.ipv6Prefix) 'Google' 'Google' $null }

    $sorted = [ordered]@{}
    foreach ($key in ($prefixes.Keys | Sort-Object)) { $sorted[$key] = $prefixes[$key].ToArray() }

    [ordered]@{
        formatVersion = 1
        kind          = 'CloudRanges'
        maxAgeDays    = 14
        pulled        = $Pulled
        note          = 'Asn and owner are each cloud''s primary network as PeeringDB lists it, not the per-prefix BGP origin. Generic services (AzureCloud, AMAZON, Google) lose a tie to a named service on the same prefix.'
        sources       = @(
            [ordered]@{ url = $azureUrl; title = "Azure IP Ranges and Service Tags - Public Cloud (changeNumber $($azure.changeNumber))"; pulled = $Pulled }
            [ordered]@{ url = $azurePage; title = 'Azure IP Ranges and Service Tags - Public Cloud download page'; pulled = $Pulled }
            [ordered]@{ url = $awsUrl; title = "AWS IP address ranges (syncToken $($aws.syncToken), created $($aws.createDate))"; pulled = $Pulled }
            [ordered]@{ url = $gcpUrl; title = "Google Cloud customer IP ranges (syncToken $($gcp.syncToken))"; pulled = $Pulled }
            [ordered]@{ url = $googUrl; title = "Google IP ranges, all services (syncToken $($goog.syncToken))"; pulled = $Pulled }
            [ordered]@{ url = 'https://www.peeringdb.com/asn/8075'; title = 'PeeringDB AS8075 Microsoft'; pulled = $Pulled }
            [ordered]@{ url = 'https://www.peeringdb.com/asn/16509'; title = 'PeeringDB AS16509 Amazon.com'; pulled = $Pulled }
            [ordered]@{ url = 'https://www.peeringdb.com/asn/15169'; title = 'PeeringDB AS15169 Google'; pulled = $Pulled }
        )
        clouds        = [ordered]@{
            Azure  = [ordered]@{ asn = 8075; owner = 'Microsoft Corporation'; version = [string]$azure.changeNumber }
            AWS    = [ordered]@{ asn = 16509; owner = 'Amazon.com, Inc.'; version = [string]$aws.syncToken }
            GCP    = [ordered]@{ asn = 15169; owner = 'Google LLC'; version = [string]$gcp.syncToken }
            Google = [ordered]@{ asn = 15169; owner = 'Google LLC'; version = [string]$goog.syncToken }
        }
        genericServices = @('AzureCloud', 'AMAZON', 'Google')
        prefixLengths = [ordered]@{
            '4' = @($lengths['4'] | Sort-Object -Descending)
            '6' = @($lengths['6'] | Sort-Object -Descending)
        }
        prefixes      = $sorted
    }
}
