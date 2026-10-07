function Get-NetworkRoute {
    <#
    .SYNOPSIS
        Lists the route table: destination, prefix length, next hop, interface and metric.

    .DESCRIPTION
        Native: Get-NetRoute on Windows, ip -j route and ip -j -6 route on Linux. The .NET floor
        has no route table to read; it derives the routes the interface configuration implies (one
        on-link route per address prefix, one default route per gateway, no metric) and says so in
        Source. NextHop is $null for an on-link route. ConvertTo-NetworkGraph turns these rows into
        the RoutesTo edges of the graph.

    .PARAMETER AddressFamily
        IPv4, IPv6, or both (default).

    .PARAMETER Tool
        Auto (native when installed, else .NET), Native, or DotNet.

    .EXAMPLE
        Get-NetworkRoute -AddressFamily IPv4 | Where-Object PrefixLength -eq 0

        The default routes.

    .OUTPUTS
        NetworkGraph.Route: Destination, PrefixLength, Cidr, NextHop, Interface, Metric, Source.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.Route')]
    param(
        [ValidateSet('IPv4', 'IPv6')]
        [string[]]
        $AddressFamily = @('IPv4', 'IPv6'),

        [ValidateSet('Auto', 'Native', 'DotNet')]
        [string]
        $Tool = 'Auto'
    )

    $candidates = $IsWindows ? @('Get-NetRoute') : @('ip')
    $chosen = Resolve-NetworkGraphTool -Tool $Tool -Candidate $candidates -CommandName 'Get-NetworkRoute'

    $rows = switch ($chosen) {
        'Get-NetRoute' {
            foreach ($row in ConvertFrom-NetworkGraphNetRoute -InputObject @(Get-NetRoute -ErrorAction SilentlyContinue)) { $row | Add-Member Source 'Get-NetRoute' -PassThru }
        }
        'ip' {
            if ('IPv4' -in $AddressFamily) {
                $run = Invoke-NetworkGraphNative -FilePath ip -ArgumentList '-j', 'route', 'show', 'table', 'main' -OkExitCodes 0
                foreach ($row in ConvertFrom-NetworkGraphIpRouteJson -Text $run.Output -Version 4) { $row | Add-Member Source $run.CommandLine -PassThru }
            }
            if ('IPv6' -in $AddressFamily) {
                $run = Invoke-NetworkGraphNative -FilePath ip -ArgumentList '-j', '-6', 'route', 'show', 'table', 'main' -OkExitCodes 0
                foreach ($row in ConvertFrom-NetworkGraphIpRouteJson -Text $run.Output -Version 6) { $row | Add-Member Source $run.CommandLine -PassThru }
            }
        }
        'DotNet' {
            foreach ($row in Get-NetworkGraphDotNetRoute) {
                $row | Add-Member Source '[System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | ForEach-Object { $_.GetIPProperties() }  # .NET floor: routes derived from addresses and gateways, no route table' -PassThru
            }
        }
    }

    foreach ($row in $rows) {
        $isV6 = $row.Destination.Contains(':')
        if (($isV6 -and 'IPv6' -notin $AddressFamily) -or (-not $isV6 -and 'IPv4' -notin $AddressFamily)) { continue }
        $row.PSObject.TypeNames.Insert(0, 'NetworkGraph.Route')
        $row
    }
}
