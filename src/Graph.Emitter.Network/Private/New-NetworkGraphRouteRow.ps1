function New-NetworkGraphRouteRow {
    # Not exported. One parsed route { Destination, PrefixLength, Cidr, NextHop, Interface,
    # InterfaceKey, Metric }, the shape every route parser returns. -Cidr takes 'addr/len', 'default'
    # (0.0.0.0/0, or ::/0 with -Version 6) or a bare address (a host route). An on-link next hop
    # (0.0.0.0, ::, empty) is $null. InterfaceKey is the key of the interface the route names.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; changes no state.')]
    param([string]$Cidr, [int]$Version = 4, [string]$NextHop, [string]$Interface, [string]$InterfaceKey, $Metric)

    if ($Cidr -eq 'default') { $Cidr = ($Version -eq 6) ? '::/0' : '0.0.0.0/0' }
    $prefix = Resolve-NetworkGraphPrefix -Cidr $Cidr
    $hop = $null
    if ($NextHop -and $NextHop -notin '0.0.0.0', '::') { $hop = (ConvertTo-NetworkGraphIpValue -Ip $NextHop).Ip }
    [pscustomobject]@{
        Destination  = ConvertFrom-NetworkGraphIpValue -Value $prefix.Network -Version $prefix.Version
        PrefixLength = $prefix.PrefixLength
        Cidr         = $prefix.Cidr
        NextHop      = $hop
        Interface    = $Interface ? $Interface : $null
        InterfaceKey = $InterfaceKey ? $InterfaceKey : $null
        Metric       = ($null -ne $Metric -and "$Metric" -ne '') ? [int]$Metric : $null
    }
}
