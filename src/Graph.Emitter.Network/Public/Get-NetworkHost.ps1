function Get-NetworkHost {
    <#
    .SYNOPSIS
        Summarises this host: name, OS, interfaces, routes, default gateways, DNS servers and
        firewall state. One object, the root node of a local graph.

    .DESCRIPTION
        Interfaces come from Get-NetworkInterface and Routes from Get-NetworkRoute (with the same
        -Tool). Firewall on Windows: Get-NetFirewallProfile (Enabled, Disabled or Partial across
        the profiles); when every profile is off, the firewall products registered with Windows
        Security Center (root/SecurityCenter2 FirewallProduct) are read too, and one that is
        enabled makes Firewall ThirdParty with its name in FirewallReason and FirewallProducts, so
        a machine protected by Norton, McAfee or similar is not reported Disabled. On Linux:
        /etc/ufw/ufw.conf (ENABLED=yes or no, readable without root), else ufw status, then
        firewall-cmd --state when the answer is still unknown. When nothing answers, Firewall is
        Unknown and FirewallReason says why.

    .PARAMETER Tool
        Passed to Get-NetworkInterface and Get-NetworkRoute. Auto, Native or DotNet.

    .EXAMPLE
        Get-NetworkHost | ConvertTo-NetworkGraph

    .OUTPUTS
        NetworkGraph.Host: HostName, Os, Platform, Interfaces, Routes, DefaultGateway, DnsServers,
        Firewall (Enabled, Disabled, Partial, ThirdParty or Unknown), FirewallReason,
        FirewallProfiles, FirewallProducts, Source.
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
    $products = @()
    $onWindows = $script:NetworkGraphPlatform -eq 'Windows'
    if ($onWindows -and (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue)) {
        $firewall = ConvertFrom-NetworkGraphNetFirewallProfile -InputObject @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
        $commands.Add('Get-NetFirewallProfile')
        if ($firewall.State -eq 'Disabled') {
            # Every Windows Firewall profile off usually means another firewall took over.
            $products = @(ConvertFrom-NetworkGraphFirewallProduct -InputObject @(Get-NetworkGraphFirewallProduct))
            $commands.Add('Get-CimInstance -Namespace root/SecurityCenter2 -ClassName FirewallProduct')
            $enabled = @($products | Where-Object Enabled)
            if ($enabled) {
                $firewall.State = 'ThirdParty'
                $firewall.Reason = "Windows Firewall off ($($firewall.Reason)); $(@($enabled.Name) -join ', ') registered and enabled in Windows Security Center"
            }
        }
    }
    elseif (-not $onWindows) {
        if (Test-Path -LiteralPath $script:NetworkGraphUfwConfPath -PathType Leaf) {
            $firewall = ConvertFrom-NetworkGraphUfwConf -Text ([System.IO.File]::ReadAllText($script:NetworkGraphUfwConfPath))
            $commands.Add("Get-Content $($script:NetworkGraphUfwConfPath)")
        }
        if (-not $firewall -and (Get-Command ufw -ErrorAction SilentlyContinue)) {
            $run = Invoke-NetworkGraphNative -FilePath ufw -ArgumentList 'status' -TimeoutSec 20 -OkExitCodes 0, 1
            $firewall = ConvertFrom-NetworkGraphUfwOutput -Text "$($run.Output)$($run.Error)"
            $commands.Add($run.CommandLine)
        }
    }
    if ((-not $firewall -or $firewall.State -eq 'Unknown') -and -not $onWindows -and (Get-Command firewall-cmd -ErrorAction SilentlyContinue)) {
        $run = Invoke-NetworkGraphNative -FilePath firewall-cmd -ArgumentList '--state' -TimeoutSec 20 -OkExitCodes 0, 1, 252
        $other = ConvertFrom-NetworkGraphFirewallCmdOutput -Text "$($run.Output)$($run.Error)"
        $commands.Add($run.CommandLine)
        if (-not $firewall -or $other.State -ne 'Unknown') { $firewall = $other }
        elseif ($firewall) { $firewall.Reason = "$($firewall.Reason); $($other.Reason)" }
    }
    if (-not $firewall) {
        $firewall = [pscustomobject]@{ State = 'Unknown'; Reason = $onWindows ? 'Get-NetFirewallProfile is not available.' : 'Neither ufw nor firewall-cmd is installed.'; Profiles = @() }
    }

    [pscustomobject]@{
        PSTypeName       = 'NetworkGraph.Host'
        HostName         = [System.Net.Dns]::GetHostName()
        Os               = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim()
        Platform         = $script:NetworkGraphPlatform
        Interfaces       = $interfaces
        Routes           = $routes
        DefaultGateway   = @($routes | Where-Object { $_.PrefixLength -eq 0 -and $_.NextHop } | ForEach-Object NextHop | Select-Object -Unique)
        DnsServers       = @($interfaces | ForEach-Object { $_.Dns } | Where-Object { $_ } | Select-Object -Unique)
        Firewall         = $firewall.State
        FirewallReason   = $firewall.Reason
        FirewallProfiles = @($firewall.Profiles)
        FirewallProducts = $products
        Source           = $commands -join '; '
    }
}
