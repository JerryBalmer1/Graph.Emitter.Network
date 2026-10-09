function ConvertFrom-NetworkGraphNetNeighbor {
    # Not exported. Get-NetNeighbor objects (live, or tests/fixtures/Get-NetNeighbor.windows.json)
    # to neighbour rows. Structured. InterfaceKey: InterfaceIndex looked up in -KeyMap
    # (Get-NetworkGraphInterfaceKeyMap).
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $InputObject,

        $KeyMap
    )

    foreach ($item in $InputObject) {
        New-NetworkGraphNeighborRow -Ip ([string]$item.IPAddress) -MacAddress ([string]$item.LinkLayerAddress) -State ([string]$item.State) -Interface ([string]$item.InterfaceAlias) `
            -InterfaceKey (Resolve-NetworkGraphInterfaceKey -KeyMap $KeyMap -Index $item.InterfaceIndex -Name $item.InterfaceAlias)
    }
}
