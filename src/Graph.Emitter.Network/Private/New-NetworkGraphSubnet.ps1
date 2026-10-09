function New-NetworkGraphSubnet {
    # Not exported. One NetworkGraph.Subnet from a Resolve-NetworkGraphPrefix result and a cloud
    # name, with the reservations from cloud-reservations.json applied.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; changes no state.')]
    param(
        [Parameter(Mandatory)]
        $Prefix,

        [Parameter(Mandatory)]
        [string]
        $Cloud
    )

    $clouds = (Get-NetworkGraphDataDocument -Kind CloudReservations)['clouds']
    $rule = $clouds[$Cloud]
    if (-not $rule) { throw [System.ArgumentException]::new("No reservation rule for cloud '$Cloud' in cloud-reservations.json.") }
    $version = $Prefix.Version
    $p = $Prefix.PrefixLength

    $applied = $rule
    if ($version -notin @($rule['versions'])) {
        if ($Cloud -ne 'None') { Write-Warning "$Cloud documents no IPv$version subnet reservations; $($Prefix.Cidr) uses the None rule." }
        $applied = $clouds['None']
    }

    $belowMinimum = $false
    if ($version -eq 4 -and $null -ne $rule['maxPrefixLength'] -and $p -gt [int]$rule['maxPrefixLength']) {
        $belowMinimum = $true
        Write-Warning "$($Prefix.Cidr) is smaller than the $Cloud minimum subnet /$($rule['maxPrefixLength'])."
    }
    if ($version -eq 4 -and $null -ne $rule['minPrefixLength'] -and $p -lt [int]$rule['minPrefixLength']) {
        Write-Warning "$($Prefix.Cidr) is larger than the $Cloud maximum subnet /$($rule['minPrefixLength'])."
    }

    $toIp = { param($value) ConvertFrom-NetworkGraphIpValue -Value $value -Version $version }
    $offsetValue = {
        param($entry)
        if ($entry['from'] -eq 'first') { $Prefix.Network + [int]$entry['offset'] } else { $Prefix.Last - [int]$entry['offset'] }
    }

    # Reserved addresses, lowest first, one row per address (the first role wins).
    $reservedByValue = [System.Collections.Generic.SortedDictionary[System.Numerics.BigInteger, object]]::new()
    if ($p -le [int]$applied['reserveUpToPrefixLength'] -and $version -in @($applied['versions'])) {
        foreach ($entry in @($applied['reserved'])) {
            $value = & $offsetValue $entry
            if ($value -lt $Prefix.Network -or $value -gt $Prefix.Last -or $reservedByValue.ContainsKey($value)) { continue }
            $reservedByValue[$value] = [pscustomobject]@{
                PSTypeName = 'NetworkGraph.ReservedAddress'
                Ip         = & $toIp $value
                Role       = [string]$entry['role']
                Source     = [string]$entry['source']
            }
        }
    }

    $usable = $Prefix.Size - $reservedByValue.Count
    $first = $null
    $last = $null
    if ($usable -gt 0) {
        $value = $Prefix.Network
        while ($reservedByValue.ContainsKey($value)) { $value = $value + 1 }
        $first = & $toIp $value
        $value = $Prefix.Last
        while ($reservedByValue.ContainsKey($value)) { $value = $value - 1 }
        $last = & $toIp $value
    }
    else {
        $usable = [System.Numerics.BigInteger]::Zero
    }

    $gateway = $null
    if ($applied['gateway'] -and $Prefix.Size -gt 1) { $gateway = & $toIp (& $offsetValue $applied['gateway']) }

    $hostMask = $Prefix.Size - 1
    $allOnes = [System.Numerics.BigInteger]::Pow(2, $Prefix.Bits) - 1

    [pscustomobject]@{
        PSTypeName        = 'NetworkGraph.Subnet'
        Cidr              = $Prefix.Cidr
        Version           = $version
        Network           = & $toIp $Prefix.Network
        Broadcast         = ($version -eq 4 -and $p -le 30) ? (& $toIp $Prefix.Last) : $null
        FirstUsable       = $first
        LastUsable        = $last
        Usable            = $usable
        Mask              = & $toIp ($allOnes - $hostMask)
        Wildcard          = & $toIp $hostMask
        PrefixLength      = $p
        Cloud             = $Cloud
        Reserved          = @($reservedByValue.Values)
        Gateway           = $gateway
        BelowCloudMinimum = $belowMinimum
    }
}
