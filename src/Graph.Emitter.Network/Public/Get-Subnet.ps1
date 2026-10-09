function Get-Subnet {
    <#
    .SYNOPSIS
        Calculates a subnet: network, broadcast, usable range and count, mask, and the addresses a
        cloud reserves.

    .DESCRIPTION
        Get-Subnet works offline on IPv4 and IPv6 with one code path (BigInteger arithmetic over the
        address bytes). Host bits are cleared, so 10.0.0.5/24 is 10.0.0.0/24.

        With -Cloud, the reserved addresses of that cloud (data/cloud-reservations.json, with the
        vendor page as Source on every Reserved row) come out of the usable range: Azure and AWS
        reserve the first four and the last address (251 usable in a /24), GCP the first two, the
        second-to-last and the last (252). Cloud None reserves the network and broadcast addresses
        of an IPv4 subnet up to /30 (254 usable in a /24); a /31 has two usable addresses (RFC 3021)
        and a /32 one. IPv6 under None reserves nothing.

        A subnet smaller than the cloud allows (Azure and GCP /29, AWS /28) is returned with
        BelowCloudMinimum $true and a warning.

    .PARAMETER Cidr
        One or more prefixes as address/length. A bare address is a /32 or /128. Accepts the
        pipeline, and objects with a Cidr property.

    .PARAMETER Address
        An address, with -PrefixLength or -Mask.

    .PARAMETER PrefixLength
        Prefix length for -Address (0-32 for IPv4, 0-128 for IPv6).

    .PARAMETER Mask
        Dotted IPv4 mask for -Address, for example 255.255.255.0.

    .PARAMETER Cloud
        None (default), Azure, AWS or GCP.

    .EXAMPLE
        Get-Subnet 10.0.0.0/24 -Cloud Azure

        251 usable, 10.0.0.4 to 10.0.0.254, gateway 10.0.0.1, five Reserved rows.

    .EXAMPLE
        Get-Subnet -Address 192.168.1.77 -Mask 255.255.255.192

        192.168.1.64/26 with 62 usable.

    .OUTPUTS
        NetworkGraph.Subnet: Cidr, Version, Network, Broadcast (IPv4 up to /30, else $null),
        FirstUsable, LastUsable, Usable (BigInteger), Mask, Wildcard, PrefixLength, Cloud, Reserved
        (NetworkGraph.ReservedAddress: Ip, Role, Source), Gateway, BelowCloudMinimum.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Cidr')]
    [OutputType('NetworkGraph.Subnet')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Cidr')]
        [string[]]
        $Cidr,

        [Parameter(Mandatory, ParameterSetName = 'PrefixLength')]
        [Parameter(Mandatory, ParameterSetName = 'Mask')]
        [string]
        $Address,

        [Parameter(Mandatory, ParameterSetName = 'PrefixLength')]
        [ValidateRange(0, 128)]
        [int]
        $PrefixLength,

        [Parameter(Mandatory, ParameterSetName = 'Mask')]
        [string]
        $Mask,

        [ValidateSet('None', 'Azure', 'AWS', 'GCP')]
        [string]
        $Cloud = 'None'
    )

    process {
        $prefixes = switch ($PSCmdlet.ParameterSetName) {
            'Cidr' { foreach ($item in $Cidr) { Resolve-NetworkGraphPrefix -Cidr $item } }
            'PrefixLength' { Resolve-NetworkGraphPrefix -Ip $Address -PrefixLength $PrefixLength }
            'Mask' { Resolve-NetworkGraphPrefix -Ip $Address -PrefixLength (ConvertFrom-SubnetMask -Mask $Mask) }
        }
        foreach ($prefix in $prefixes) {
            New-NetworkGraphSubnet -Prefix $prefix -Cloud $Cloud
        }
    }
}
