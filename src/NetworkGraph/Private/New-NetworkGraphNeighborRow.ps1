function New-NetworkGraphNeighborRow {
    # Not exported. One parsed neighbour { Ip, MacAddress, State, Interface, InterfaceKey }, the shape
    # every neighbour parser returns. State is title case (Reachable, Stale, Permanent, Incomplete,
    # ...). InterfaceKey is the key of the interface the neighbour was seen on.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; changes no state.')]
    param([string]$Ip, [string]$MacAddress, [string]$State, [string]$Interface, [string]$InterfaceKey)

    $title = $null
    if ($State) { $title = $State.Substring(0, 1).ToUpperInvariant() + $State.Substring(1).ToLowerInvariant() }
    [pscustomobject]@{
        Ip           = (ConvertTo-NetworkGraphIpValue -Ip $Ip).Ip
        MacAddress   = ConvertTo-NetworkGraphMac -MacAddress $MacAddress
        State        = $title
        Interface    = $Interface ? $Interface : $null
        InterfaceKey = $InterfaceKey ? $InterfaceKey : $null
    }
}
