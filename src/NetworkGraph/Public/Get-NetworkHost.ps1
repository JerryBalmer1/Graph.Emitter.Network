function Get-NetworkHost {
    <#
    .SYNOPSIS
        Summarises this host: name, OS, interfaces, routes, default gateways, DNS servers and
        firewall state. One object, the root node of a local graph.

    .DESCRIPTION
        Interfaces come from Get-NetworkInterface and Routes from Get-NetworkRoute (with the same
        -Tool). Firewall: Get-NetFirewallProfile on Windows (Enabled, Disabled or Partial across
        the profiles); on Linux ufw status, else firewall-cmd --state, when installed. When no
        firewall tool is installed, or it cannot answer (ufw needs root), Firewall is Unknown and
        FirewallReason says why.

    .PARAMETER Tool
        Passed to Get-NetworkInterface and Get-NetworkRoute. Auto, Native or DotNet.

    .EXAMPLE
        Get-NetworkHost | ConvertTo-NetworkGraph

    .OUTPUTS
        NetworkGraph.Host: HostName, Os, Platform, Interfaces, Routes, DefaultGateway, DnsServers,
        Firewall, FirewallReason, FirewallProfiles, Source.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.Host')]
    param(
        [ValidateSet('Auto', 'Native', 'DotNet')]
        [string]
        $Tool = 'Auto'
    )

    $interfaces = @(Get-NetworkInterface -Tool $Tool)
    $routes = @(Get-NetworkRoute -Tool $Tool)
    $commands = [System.Collections.Generic.List[string]]::new()
    $commands.Add('[System.Net.Dns]::GetHostName()')
    foreach ($text in @($interfaces.Source) + @($routes.Source) | Select-Object -Unique) { $commands.Add($text) }

    $firewall = $null
    if ($IsWindows -and (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue)) {
        $firewall = ConvertFrom-NetworkGraphNetFirewallProfile -InputObject @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
        $commands.Add('Get-NetFirewallProfile')
    }
    elseif (-not $IsWindows -and (Get-Command ufw -ErrorAction SilentlyContinue)) {
        $run = Invoke-NetworkGraphNative -FilePath ufw -ArgumentList 'status' -TimeoutSec 20
        $firewall = ConvertFrom-NetworkGraphUfwOutput -Text "$($run.Output)$($run.Error)"
        $commands.Add($run.CommandLine)
    }
    if ((-not $firewall -or $firewall.State -eq 'Unknown') -and -not $IsWindows -and (Get-Command firewall-cmd -ErrorAction SilentlyContinue)) {
        $run = Invoke-NetworkGraphNative -FilePath firewall-cmd -ArgumentList '--state' -TimeoutSec 20
        $other = ConvertFrom-NetworkGraphFirewallCmdOutput -Text "$($run.Output)$($run.Error)"
        $commands.Add($run.CommandLine)
        if (-not $firewall -or $other.State -ne 'Unknown') { $firewall = $other }
        elseif ($firewall) { $firewall.Reason = "$($firewall.Reason); $($other.Reason)" }
    }
    if (-not $firewall) {
        $firewall = [pscustomobject]@{ State = 'Unknown'; Reason = $IsWindows ? 'Get-NetFirewallProfile is not available.' : 'Neither ufw nor firewall-cmd is installed.'; Profiles = @() }
    }

    [pscustomobject]@{
        PSTypeName       = 'NetworkGraph.Host'
        HostName         = [System.Net.Dns]::GetHostName()
        Os               = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim()
        Platform         = $IsWindows ? 'Windows' : ($IsLinux ? 'Linux' : ($IsMacOS ? 'macOS' : 'Unknown'))
        Interfaces       = $interfaces
        Routes           = $routes
        DefaultGateway   = @($routes | Where-Object { $_.PrefixLength -eq 0 -and $_.NextHop } | ForEach-Object NextHop | Select-Object -Unique)
        DnsServers       = @($interfaces | ForEach-Object { $_.Dns } | Where-Object { $_ } | Select-Object -Unique)
        Firewall         = $firewall.State
        FirewallReason   = $firewall.Reason
        FirewallProfiles = @($firewall.Profiles)
        Source           = $commands -join '; '
    }
}
