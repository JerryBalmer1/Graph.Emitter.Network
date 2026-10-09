function Get-NetworkNeighbor {
    <#
    .SYNOPSIS
        Lists the ARP and IPv6 neighbour table: the addresses and MAC addresses this host has
        seen on its links.

    .DESCRIPTION
        Native: Get-NetNeighbor on Windows, ip -j neigh on Linux, and arp -a on either when the
        first is missing. The .NET floor reads /proc/net/arp on Linux (IPv4 only); .NET has no API
        for the neighbour table, so on Windows and on macOS (no /proc) -Tool DotNet is a terminating
        error. Vendor comes
        from Get-MacAddressVendor and is $null for a locally-administered (often randomised) MAC.
        InterfaceKey is the key of the interface the neighbour was seen on (the interface GUID on
        Windows, the ifindex on Linux; see Get-NetworkInterface), looked up by index or name in this
        host's interface table at the same moment; Source names that lookup after the command.

    .PARAMETER Tool
        Auto (native when installed, else .NET), Native, or DotNet.

    .PARAMETER IncludeUnresolved
        Keep rows with no MAC address (Incomplete, Unreachable, Failed).

    .EXAMPLE
        Get-NetworkNeighbor | Where-Object Vendor

    .OUTPUTS
        NetworkGraph.Neighbor: Ip, MacAddress, Vendor, State, Interface, InterfaceKey, Source.
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

    $candidates = ($script:NetworkGraphPlatform -eq 'Windows') ? @('Get-NetNeighbor', 'arp') : @('ip', 'arp')
    $noDotNet = switch ($script:NetworkGraphPlatform) {
        'Windows' { '.NET has no API that reads the neighbour table on Windows.' }
        'macOS' { 'There is no .NET floor on macOS: the floor reads /proc/net/arp, which exists only on Linux.' }
        default { $null }
    }
    $chosen = Resolve-NetworkGraphTool -Tool $Tool -Candidate $candidates -CommandName 'Get-NetworkNeighbor' -NoDotNet $noDotNet
    $keys = Get-NetworkGraphInterfaceKeyMap
    $withKey = { param($Source) "$Source; $($keys.Source)" }

    $rows = switch ($chosen) {
        'Get-NetNeighbor' {
            foreach ($row in ConvertFrom-NetworkGraphNetNeighbor -InputObject @(Get-NetNeighbor -ErrorAction SilentlyContinue) -KeyMap $keys) { $row | Add-Member Source (& $withKey 'Get-NetNeighbor') -PassThru }
        }
        'ip' {
            $run = Invoke-NetworkGraphNative -FilePath ip -ArgumentList '-j', 'neigh' -OkExitCodes 0
            foreach ($row in ConvertFrom-NetworkGraphIpNeighJson -Text $run.Output -KeyMap $keys) { $row | Add-Member Source (& $withKey $run.CommandLine) -PassThru }
        }
        'arp' {
            $run = Invoke-NetworkGraphNative -FilePath arp -ArgumentList '-a' -OkExitCodes 0
            foreach ($row in ConvertFrom-NetworkGraphArpOutput -Text $run.Output -ExitCode $run.ExitCode -KeyMap $keys) { $row | Add-Member Source (& $withKey $run.CommandLine) -PassThru }
        }
        'DotNet' {
            $text = [System.IO.File]::ReadAllText('/proc/net/arp')
            foreach ($row in ConvertFrom-NetworkGraphProcNetArp -Text $text -KeyMap $keys) { $row | Add-Member Source "[System.IO.File]::ReadAllText('/proc/net/arp'); $($keys.Source)  # .NET floor: IPv4 only" -PassThru }
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
            PSTypeName   = 'NetworkGraph.Neighbor'
            Ip           = $row.Ip
            MacAddress   = $row.MacAddress
            Vendor       = $vendor
            State        = $row.State
            Interface    = $row.Interface
            InterfaceKey = $row.InterfaceKey
            Source       = $row.Source
        }
    }
}
