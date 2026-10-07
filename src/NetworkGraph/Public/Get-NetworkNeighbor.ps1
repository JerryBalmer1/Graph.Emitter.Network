function Get-NetworkNeighbor {
    <#
    .SYNOPSIS
        Lists the ARP and IPv6 neighbour table: the addresses and MAC addresses this host has
        seen on its links.

    .DESCRIPTION
        Native: Get-NetNeighbor on Windows, ip -j neigh on Linux, and arp -a on either when the
        first is missing. The .NET floor reads /proc/net/arp on Linux (IPv4 only); .NET has no API
        for the neighbour table, so on Windows -Tool DotNet is a terminating error. Vendor comes
        from Get-MacAddressVendor and is $null for a locally-administered (often randomised) MAC.

    .PARAMETER Tool
        Auto (native when installed, else .NET), Native, or DotNet.

    .PARAMETER IncludeUnresolved
        Keep rows with no MAC address (Incomplete, Unreachable, Failed).

    .EXAMPLE
        Get-NetworkNeighbor | Where-Object Vendor

    .OUTPUTS
        NetworkGraph.Neighbor: Ip, MacAddress, Vendor, State, Interface, Source.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.Neighbor')]
    param(
        [ValidateSet('Auto', 'Native', 'DotNet')]
        [string]
        $Tool = 'Auto',

        [switch]
        $IncludeUnresolved
    )

    $candidates = $IsWindows ? @('Get-NetNeighbor', 'arp') : @('ip', 'arp')
    $noDotNet = $IsWindows ? '.NET has no API that reads the neighbour table on Windows.' : $null
    $chosen = Resolve-NetworkGraphTool -Tool $Tool -Candidate $candidates -CommandName 'Get-NetworkNeighbor' -NoDotNet $noDotNet

    $rows = switch ($chosen) {
        'Get-NetNeighbor' {
            foreach ($row in ConvertFrom-NetworkGraphNetNeighbor -InputObject @(Get-NetNeighbor -ErrorAction SilentlyContinue)) { $row | Add-Member Source 'Get-NetNeighbor' -PassThru }
        }
        'ip' {
            $run = Invoke-NetworkGraphNative -FilePath ip -ArgumentList '-j', 'neigh'
            foreach ($row in ConvertFrom-NetworkGraphIpNeighJson -Text $run.Output) { $row | Add-Member Source $run.CommandLine -PassThru }
        }
        'arp' {
            $run = Invoke-NetworkGraphNative -FilePath arp -ArgumentList '-a'
            foreach ($row in ConvertFrom-NetworkGraphArpOutput -Text $run.Output) { $row | Add-Member Source $run.CommandLine -PassThru }
        }
        'DotNet' {
            $text = [System.IO.File]::ReadAllText('/proc/net/arp')
            foreach ($row in ConvertFrom-NetworkGraphProcNetArp -Text $text) { $row | Add-Member Source '[System.IO.File]::ReadAllText(''/proc/net/arp'') (.NET floor: IPv4 only)' -PassThru }
        }
    }

    $vendors = @{}
    foreach ($row in $rows) {
        if (-not $row.MacAddress -and -not $IncludeUnresolved) { continue }
        $vendor = $null
        if ($row.MacAddress) {
            if (-not $vendors.ContainsKey($row.MacAddress)) {
                $vendors[$row.MacAddress] = try { (Get-MacAddressVendor -MacAddress $row.MacAddress -ErrorAction Stop).Vendor } catch { Write-Verbose $_.Exception.Message; $null }
            }
            $vendor = $vendors[$row.MacAddress]
        }
        [pscustomobject]@{
            PSTypeName = 'NetworkGraph.Neighbor'
            Ip         = $row.Ip
            MacAddress = $row.MacAddress
            Vendor     = $vendor
            State      = $row.State
            Interface  = $row.Interface
            Source     = $row.Source
        }
    }
}
