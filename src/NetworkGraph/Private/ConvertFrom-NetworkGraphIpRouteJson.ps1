function ConvertFrom-NetworkGraphIpRouteJson {
    # Not exported. 'ip -j route' (or 'ip -j -6 route' with -Version 6) JSON to route rows.
    # Structured: dst ('default', a prefix, or a host address), gateway, dev, metric. Pinned by
    # tests/fixtures/ip-route.linux.json and ip-route6.linux.json. InterfaceKey: dev looked up in
    # -KeyMap (Get-NetworkGraphInterfaceKeyMap).
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text,

        [ValidateSet(4, 6)]
        [int]
        $Version = 4,

        $KeyMap
    )

    if (-not $Text.Trim()) { return }
    foreach ($item in @($Text | ConvertFrom-Json -AsHashtable)) {
        if ($item['type'] -and $item['type'] -notin 'unicast') { continue }
        New-NetworkGraphRouteRow -Cidr $item['dst'] -Version $Version -NextHop $item['gateway'] -Interface $item['dev'] `
            -InterfaceKey (Resolve-NetworkGraphInterfaceKey -KeyMap $KeyMap -Name $item['dev']) -Metric $item['metric']
    }
}
