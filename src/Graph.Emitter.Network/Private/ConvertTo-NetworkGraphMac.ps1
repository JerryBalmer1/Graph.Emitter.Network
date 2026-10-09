function ConvertTo-NetworkGraphMac {
    # Not exported. A MAC address in any notation to upper-case dash form (00-1A-2B-3C-4D-5E), or
    # $null for an empty, incomplete or all-zero address.
    param([AllowEmptyString()][AllowNull()][string]$MacAddress)

    $hex = ([string]$MacAddress) -replace '[-:.\s]', ''
    if ($hex -notmatch '^[0-9A-Fa-f]{12}$' -or $hex -match '^0{12}$') { return $null }
    (($hex.ToUpperInvariant() -split '(..)') -ne '') -join '-'
}
