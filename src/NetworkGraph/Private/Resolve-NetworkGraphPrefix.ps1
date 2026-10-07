function Resolve-NetworkGraphPrefix {
    # Not exported. A prefix from 'ip/len' text, or an address and a prefix length, as
    # { Cidr, Version, Bits, PrefixLength, Network, Last, Size, Value } with Network, Last, Size
    # and Value (the address given) as BigInteger. Host bits are cleared: 10.0.0.5/24 is
    # 10.0.0.0/24. A bare address is a /32 or /128.
    [CmdletBinding(DefaultParameterSetName = 'Cidr')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Cidr')]
        [string]
        $Cidr,

        [Parameter(Mandatory, ParameterSetName = 'Address')]
        [string]
        $Ip,

        [Parameter(Mandatory, ParameterSetName = 'Address')]
        [int]
        $PrefixLength
    )

    if ($PSCmdlet.ParameterSetName -eq 'Cidr') {
        $parts = $Cidr.Trim().Split('/')
        if ($parts.Count -gt 2) { throw [System.ArgumentException]::new("'$Cidr' is not a prefix; write it as address/length, for example 10.0.0.0/24.") }
        $Ip = $parts[0]
        $PrefixLength = -1
        if ($parts.Count -eq 2 -and -not [int]::TryParse($parts[1], [ref]$PrefixLength)) {
            throw [System.ArgumentException]::new("'$Cidr' has a prefix length that is not a number.")
        }
    }

    $address = ConvertTo-NetworkGraphIpValue -Ip $Ip
    if ($PrefixLength -eq -1) { $PrefixLength = $address.Bits }
    if ($PrefixLength -lt 0 -or $PrefixLength -gt $address.Bits) {
        throw [System.ArgumentException]::new("Prefix length $PrefixLength is out of range for IPv$($address.Version) (0-$($address.Bits)).")
    }

    $size = [System.Numerics.BigInteger]::Pow(2, $address.Bits - $PrefixLength)
    $network = $address.Value - [System.Numerics.BigInteger]::Remainder($address.Value, $size)
    [pscustomobject]@{
        Cidr         = '{0}/{1}' -f (ConvertFrom-NetworkGraphIpValue -Value $network -Version $address.Version), $PrefixLength
        Version      = $address.Version
        Bits         = $address.Bits
        PrefixLength = $PrefixLength
        Network      = $network
        Last         = $network + $size - 1
        Size         = $size
        Value        = $address.Value
    }
}
