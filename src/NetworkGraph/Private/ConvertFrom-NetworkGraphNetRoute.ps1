function ConvertFrom-NetworkGraphNetRoute {
    # Not exported. Get-NetRoute objects (live, or tests/fixtures/Get-NetRoute.windows.json) to route
    # rows. Structured. Metric is RouteMetric (Windows adds the interface metric when it chooses).
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $InputObject
    )

    foreach ($item in $InputObject) {
        New-NetworkGraphRouteRow -Cidr ([string]$item.DestinationPrefix) -NextHop ([string]$item.NextHop) -Interface ([string]$item.InterfaceAlias) -Metric $item.RouteMetric
    }
}
