function Get-NetworkGraphNetIPConfiguration {
    # Not exported. Get-NetIPConfiguration -All flattened to plain values (its objects nest CIM
    # instances): InterfaceAlias, InterfaceIndex, InterfaceGuid (NetAdapter.InterfaceGuid, the
    # InterfaceKey), InterfaceDescription, Status, MacAddress, Ip ('addr/len'), Gateway, Dns. tests/fixtures/Get-NetIPConfiguration.windows.json was captured through this
    # function, and ConvertFrom-NetworkGraphNetIPConfiguration reads this shape.
    foreach ($item in Get-NetIPConfiguration -All -ErrorAction SilentlyContinue) {
        $addresses = @($item.IPv4Address) + @($item.IPv6Address) + @($item.IPv6LinkLocalAddress) | Where-Object { $_ }
        [pscustomobject]@{
            InterfaceAlias       = [string]$item.InterfaceAlias
            InterfaceIndex       = [int]$item.InterfaceIndex
            InterfaceGuid        = [string]$item.NetAdapter.InterfaceGuid
            InterfaceDescription = [string]$item.InterfaceDescription
            Status               = [string]$item.NetAdapter.Status
            MacAddress           = [string]$item.NetAdapter.MacAddress
            Ip                   = @($addresses | ForEach-Object { '{0}/{1}' -f $_.IPAddress, $_.PrefixLength })
            Gateway              = @(@($item.IPv4DefaultGateway) + @($item.IPv6DefaultGateway) | Where-Object { $_ } | ForEach-Object { [string]$_.NextHop })
            Dns                  = @(@($item.DNSServer) | Where-Object { $_ } | ForEach-Object { $_.ServerAddresses } | Select-Object -Unique)
        }
    }
}
