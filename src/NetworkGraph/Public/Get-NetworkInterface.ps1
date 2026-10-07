function Get-NetworkInterface {
    <#
    .SYNOPSIS
        Lists network adapters with their addresses, prefix lengths, MAC address and vendor,
        gateways, DNS servers and status.

    .DESCRIPTION
        Native: Get-NetIPConfiguration -All on Windows; ip -j addr with ip -j route (gateways) and
        /etc/resolv.conf (DNS servers, the same for every interface) on Linux. The .NET floor,
        System.Net.NetworkInformation.NetworkInterface, gives the same fields on every platform.
        Ip and PrefixLength are parallel arrays. Vendor is $null for a locally-administered MAC.

    .PARAMETER Name
        Adapter names to keep; wildcards allowed.

    .PARAMETER Tool
        Auto (native when installed, else .NET), Native, or DotNet.

    .EXAMPLE
        Get-NetworkInterface | Where-Object Status -eq Up

    .OUTPUTS
        NetworkGraph.Interface: Name, Description, Status, Ip, PrefixLength, MacAddress, Vendor,
        Gateway, Dns, Source.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.Interface')]
    param(
        [Parameter(Position = 0)]
        [SupportsWildcards()]
        [string[]]
        $Name = '*',

        [ValidateSet('Auto', 'Native', 'DotNet')]
        [string]
        $Tool = 'Auto'
    )

    $candidates = $IsWindows ? @('Get-NetIPConfiguration') : @('ip')
    $chosen = Resolve-NetworkGraphTool -Tool $Tool -Candidate $candidates -CommandName 'Get-NetworkInterface'

    $rows = switch ($chosen) {
        'Get-NetIPConfiguration' {
            foreach ($row in ConvertFrom-NetworkGraphNetIPConfiguration -InputObject @(Get-NetworkGraphNetIPConfiguration)) { $row | Add-Member Source 'Get-NetIPConfiguration -All' -PassThru }
        }
        'ip' {
            $addr = Invoke-NetworkGraphNative -FilePath ip -ArgumentList '-j', 'addr' -OkExitCodes 0
            $route = Invoke-NetworkGraphNative -FilePath ip -ArgumentList '-j', 'route', 'show', 'table', 'main' -OkExitCodes 0
            $resolv = (Test-Path -LiteralPath '/etc/resolv.conf') ? [System.IO.File]::ReadAllText('/etc/resolv.conf') : ''
            foreach ($row in ConvertFrom-NetworkGraphIpAddrJson -Text $addr.Output -RouteText $route.Output -ResolvConf $resolv) {
                $row | Add-Member Source "$($addr.CommandLine); $($route.CommandLine); Get-Content /etc/resolv.conf" -PassThru
            }
        }
        'DotNet' {
            foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
                $properties = $adapter.GetIPProperties()
                New-NetworkGraphInterfaceRow -Name $adapter.Name -Description $adapter.Description -Status ([string]$adapter.OperationalStatus) `
                    -MacAddress $adapter.GetPhysicalAddress().ToString() `
                    -Address @($properties.UnicastAddresses | ForEach-Object { '{0}/{1}' -f $_.Address, $_.PrefixLength }) `
                    -Gateway @($properties.GatewayAddresses | ForEach-Object { $_.Address.ToString() }) `
                    -Dns @($properties.DnsAddresses | ForEach-Object { $_.ToString() } | Select-Object -Unique) |
                    Add-Member Source '[System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()' -PassThru
            }
        }
    }

    foreach ($row in $rows) {
        $keep = $false
        foreach ($pattern in $Name) { if ($row.Name -like $pattern) { $keep = $true } }
        if (-not $keep) { continue }
        $vendor = $null
        if ($row.MacAddress) {
            $vendor = try { (Get-MacAddressVendor -MacAddress $row.MacAddress -ErrorAction Stop).Vendor } catch { Write-Verbose $_.Exception.Message; $null }
        }
        [pscustomobject]@{
            PSTypeName   = 'NetworkGraph.Interface'
            Name         = $row.Name
            Description  = $row.Description
            Status       = $row.Status
            Ip           = $row.Ip
            PrefixLength = $row.PrefixLength
            MacAddress   = $row.MacAddress
            Vendor       = $vendor
            Gateway      = $row.Gateway
            Dns          = $row.Dns
            Source       = $row.Source
        }
    }
}
