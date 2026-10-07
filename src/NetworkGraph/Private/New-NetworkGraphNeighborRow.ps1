function New-NetworkGraphNeighborRow {
    # Not exported. One parsed neighbour { Ip, MacAddress, State, Interface }, the shape every
    # neighbour parser returns. State is title case (Reachable, Stale, Permanent, Incomplete, ...).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; changes no state.')]
    param([string]$Ip, [string]$MacAddress, [string]$State, [string]$Interface)

    $title = $null
    if ($State) { $title = $State.Substring(0, 1).ToUpperInvariant() + $State.Substring(1).ToLowerInvariant() }
    [pscustomobject]@{
        Ip         = (ConvertTo-NetworkGraphIpValue -Ip $Ip).Ip
        MacAddress = ConvertTo-NetworkGraphMac -MacAddress $MacAddress
        State      = $title
        Interface  = $Interface ? $Interface : $null
    }
}
