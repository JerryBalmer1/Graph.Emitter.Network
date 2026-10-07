function ConvertFrom-NetworkGraphNetNeighbor {
    # Not exported. Get-NetNeighbor objects (live, or tests/fixtures/Get-NetNeighbor.windows.json)
    # to neighbour rows. Structured.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $InputObject
    )

    foreach ($item in $InputObject) {
        New-NetworkGraphNeighborRow -Ip ([string]$item.IPAddress) -MacAddress ([string]$item.LinkLayerAddress) -State ([string]$item.State) -Interface ([string]$item.InterfaceAlias)
    }
}
