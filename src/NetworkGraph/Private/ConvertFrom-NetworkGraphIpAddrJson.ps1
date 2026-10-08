function ConvertFrom-NetworkGraphIpAddrJson {
    # Not exported. 'ip -j addr' JSON to interface rows. Structured. Gateways come from
    # 'ip -j route' JSON (-RouteText: default routes on the same device) and DNS servers from
    # /etc/resolv.conf text (-ResolvConf: nameserver lines), which applies to every interface.
    # InterfaceKey is ifindex.
    # Pinned by tests/fixtures/ip-addr.linux.json, ip-route.linux.json, resolv.conf.linux.txt.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text,

        [AllowEmptyString()]
        [string]
        $RouteText,

        [AllowEmptyString()]
        [string]
        $ResolvConf
    )

    $gateways = @{}
    if ($RouteText) {
        foreach ($route in @($RouteText | ConvertFrom-Json -AsHashtable)) {
            if ($route['dst'] -eq 'default' -and $route['gateway']) {
                $gateways[$route['dev']] = @($gateways[$route['dev']]) + @($route['gateway']) | Where-Object { $_ }
            }
        }
    }
    $dns = @()
    if ($ResolvConf) { $dns = @([regex]::Matches($ResolvConf, '(?m)^\s*nameserver\s+(\S+)') | ForEach-Object { $_.Groups[1].Value }) }

    foreach ($link in @($Text | ConvertFrom-Json -AsHashtable)) {
        $addresses = @(foreach ($info in @($link['addr_info'])) { '{0}/{1}' -f $info['local'], $info['prefixlen'] })
        $status = [string]$link['operstate']
        if ($status -eq 'UNKNOWN' -and @($link['flags']) -contains 'UP') { $status = 'Up' }
        New-NetworkGraphInterfaceRow -Name $link['ifname'] -InterfaceKey "$($link['ifindex'])" -Description $link['link_type'] -Status $status.ToLowerInvariant() `
            -MacAddress $link['address'] -Address $addresses -Gateway @($gateways[$link['ifname']]) -Dns $dns
    }
}
