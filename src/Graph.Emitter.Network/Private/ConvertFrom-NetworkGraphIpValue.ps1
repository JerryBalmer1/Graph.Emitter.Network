function ConvertFrom-NetworkGraphIpValue {
    # Not exported. The text form of an address held as an unsigned BigInteger (see
    # ConvertTo-NetworkGraphIpValue): dotted for version 4, compressed RFC 5952 form for 6.
    param(
        [Parameter(Mandatory)]
        [System.Numerics.BigInteger]
        $Value,

        [Parameter(Mandatory)]
        [ValidateSet(4, 6)]
        [int]
        $Version
    )

    $length = ($Version -eq 4) ? 4 : 16
    $bytes = [byte[]]::new($length)
    $rest = $Value
    for ($i = $length - 1; $i -ge 0; $i--) {
        $bytes[$i] = [byte][int][System.Numerics.BigInteger]::Remainder($rest, 256)
        $rest = [System.Numerics.BigInteger]::Divide($rest, 256)
    }
    [System.Net.IPAddress]::new($bytes).ToString()
}
