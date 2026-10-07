function Get-NetworkGraphDotNetRoute {
    # Not exported. The .NET floor for routes. .NET has no route table API, so this derives what
    # the interface configuration implies: one on-link route per unicast address prefix, and one
    # default route (0.0.0.0/0 or ::/0) per gateway. Metric is unknown ($null).
    foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($adapter.OperationalStatus -ne 'Up') { continue }
        $properties = $adapter.GetIPProperties()
        foreach ($unicast in $properties.UnicastAddresses) {
            $text = $unicast.Address.ToString()
            New-NetworkGraphRouteRow -Cidr "$text/$($unicast.PrefixLength)" -Interface $adapter.Name
        }
        foreach ($gateway in $properties.GatewayAddresses) {
            $address = $gateway.Address
            if ($address.ToString() -in '0.0.0.0', '::') { continue }
            $version = ($address.AddressFamily -eq 'InterNetworkV6') ? 6 : 4
            New-NetworkGraphRouteRow -Cidr default -Version $version -NextHop $address.ToString() -Interface $adapter.Name
        }
    }
}
