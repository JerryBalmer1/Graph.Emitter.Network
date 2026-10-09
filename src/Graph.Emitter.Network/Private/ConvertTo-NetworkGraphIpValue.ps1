function ConvertTo-NetworkGraphIpValue {
    # Not exported. One IP address as { Ip, Version, Bits, Value }: Value is the unsigned
    # big-endian BigInteger of the address bytes, so IPv4 and IPv6 share one code path. Accepts
    # [brackets] and a %zone suffix. An IPv4 address must have four dotted parts (IPAddress.Parse
    # would read '10.1' as 10.0.0.1). An IPv4-mapped IPv6 address stays IPv6 unless -Unmap.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Ip,

        [switch]
        $Unmap
    )

    $text = $Ip.Trim()
    if ($text.StartsWith('[') -and $text.EndsWith(']')) { $text = $text.Substring(1, $text.Length - 2) }
    $zone = $text.IndexOf('%')
    if ($zone -ge 0) { $text = $text.Substring(0, $zone) }

    $parsed = $null
    $looksV4 = $text -match '^\d{1,3}(\.\d{1,3}){3}$'
    if (($text.Contains(':') -or $looksV4) -and [System.Net.IPAddress]::TryParse($text, [ref]$parsed)) {
        if ($Unmap -and $parsed.IsIPv4MappedToIPv6) { $parsed = $parsed.MapToIPv4() }
    }
    else {
        throw [System.ArgumentException]::new("'$Ip' is not an IPv4 address (four dotted numbers) or an IPv6 address.")
    }

    $bytes = $parsed.GetAddressBytes()
    $value = [System.Numerics.BigInteger]::Zero
    foreach ($byte in $bytes) { $value = $value * 256 + $byte }
    $version = ($bytes.Length -eq 4) ? 4 : 6

    [pscustomobject]@{
        Ip      = (ConvertFrom-NetworkGraphIpValue -Value $value -Version $version)
        Version = $version
        Bits    = $bytes.Length * 8
        Value   = $value
    }
}
