function New-NetworkGraphInterfaceRow {
    # Not exported. One parsed interface { Name, Description, Status, MacAddress, Ip, PrefixLength,
    # Gateway, Dns }, the shape every interface parser returns. -Address takes 'addr/len' strings;
    # Ip and PrefixLength are parallel arrays. Status is Up, Down or the tool's word.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; changes no state.')]
    param(
        [string]$Name,
        [string]$Description,
        [string]$Status,
        [string]$MacAddress,
        [string[]]$Address = @(),
        [string[]]$Gateway = @(),
        [string[]]$Dns = @()
    )

    $ips = [System.Collections.Generic.List[string]]::new()
    $lengths = [System.Collections.Generic.List[int]]::new()
    foreach ($item in $Address) {
        $parts = $item.Split('/')
        $ips.Add((ConvertTo-NetworkGraphIpValue -Ip $parts[0]).Ip)
        $lengths.Add(($parts.Count -gt 1) ? [int]$parts[1] : ($parts[0].Contains(':') ? 128 : 32))
    }
    $state = switch -Regex ($Status) { '^(up|connected)$' { 'Up' } '^(down|disconnected|not ?present)$' { 'Down' } default { $Status } }
    [pscustomobject]@{
        Name         = $Name
        Description  = $Description ? $Description : $null
        Status       = $state ? $state : $null
        MacAddress   = ConvertTo-NetworkGraphMac -MacAddress $MacAddress
        Ip           = $ips.ToArray()
        PrefixLength = $lengths.ToArray()
        Gateway      = @($Gateway | Where-Object { $_ -and $_ -notin '0.0.0.0', '::' })
        Dns          = @($Dns | Where-Object { $_ })
    }
}
