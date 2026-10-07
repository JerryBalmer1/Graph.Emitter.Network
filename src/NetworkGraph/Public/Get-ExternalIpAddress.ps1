function Get-ExternalIpAddress {
    <#
    .SYNOPSIS
        Asks several HTTPS services what public address this host's traffic leaves from.

    .DESCRIPTION
        Every endpoint in data/ip-sources.json (ipify, AWS checkip, icanhazip) is asked over
        HTTPS, and every answer is kept in Answers. Ip is the answer most endpoints gave; Agreed is
        $false when they differ (two egress paths, a proxy, a VPN split tunnel).

        -Rdap adds Network, Owner, Country, Cidr and, when the registry publishes it, Asn, from
        RDAP: rdap.org first, which redirects to the regional registry, else the registry named in
        the IANA bootstrap file.

        What a host can and cannot see about routing: it sees its own routes, the hops a trace
        reveals, and what registries say about an address. It cannot see BGP: which networks
        announce a prefix, or the path between autonomous systems. This module does no BGP lookup.

        Native: curl (-s --proto =https); the .NET floor is Invoke-WebRequest (HttpClient).

    .PARAMETER Rdap
        Add registration data for the address.

    .PARAMETER TimeoutSec
        Per request. Default 10.

    .PARAMETER Tool
        Auto (curl when installed, else .NET), Native, or DotNet.

    .EXAMPLE
        Get-ExternalIpAddress -Rdap

    .OUTPUTS
        NetworkGraph.ExternalIp: Ip, Version, Agreed, Answers (Endpoint, Url, Ip, Error), Network,
        Owner, Country, Cidr, Asn, RdapUrl, Source.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.ExternalIp')]
    param(
        [switch]
        $Rdap,

        [ValidateRange(1, 300)]
        [int]
        $TimeoutSec = 10,

        [ValidateSet('Auto', 'Native', 'DotNet')]
        [string]
        $Tool = 'Auto'
    )

    $chosen = Resolve-NetworkGraphTool -Tool $Tool -Candidate @('curl') -CommandName 'Get-ExternalIpAddress'
    $endpoints = @((Get-NetworkGraphDataDocument -Kind IpSources)['endpoints'])
    $commands = [System.Collections.Generic.List[string]]::new()

    $answers = foreach ($endpoint in $endpoints) {
        $text = $null
        $problem = $null
        try {
            if ($chosen -eq 'curl') {
                $run = Invoke-NetworkGraphNative -FilePath curl -ArgumentList '-s', '-S', '--proto', '=https', '-m', "$TimeoutSec", $endpoint['url'] -TimeoutSec ($TimeoutSec + 5)
                $commands.Add($run.CommandLine)
                if ($run.ExitCode -ne 0) { throw $run.Error.Trim() }
                $text = $run.Output
            }
            else {
                $commands.Add("Invoke-WebRequest $($endpoint['url'])")
                $text = (Invoke-NetworkGraphWebRequest -Uri $endpoint['url'] -TimeoutSec $TimeoutSec).Content
            }
            $answer = ($endpoint['format'] -eq 'json') ? ($text | ConvertFrom-Json -AsHashtable)[$endpoint['field']] : $text
            $ip = (ConvertTo-NetworkGraphIpValue -Ip ([string]$answer).Trim() -Unmap).Ip
        }
        catch {
            $ip = $null
            $problem = "$_"
        }
        [pscustomobject]@{ Endpoint = $endpoint['name']; Url = $endpoint['url']; Ip = $ip; Error = $problem }
    }

    $votes = @($answers | Where-Object Ip | Group-Object Ip | Sort-Object Count -Descending)
    if (-not $votes) {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.Net.WebException]::new("No endpoint answered: $(($answers | ForEach-Object { "$($_.Endpoint): $($_.Error)" }) -join '; '). Check the connection or proxy, then run Get-ExternalIpAddress again."),
                'NoExternalAddress', [System.Management.Automation.ErrorCategory]::ConnectionError, $null))
    }
    $ip = $votes[0].Name

    $registration = $null
    if ($Rdap) {
        try { $registration = Get-NetworkGraphRdap -Ip $ip }
        catch { Write-Error -Message "RDAP lookup for $ip failed: $($_.Exception.Message)" -ErrorId 'RdapFailed' -Category ConnectionError -TargetObject $ip }
        if ($registration) { $commands.Add("RDAP $($registration.RdapUrl)") }
    }

    [pscustomobject]@{
        PSTypeName = 'NetworkGraph.ExternalIp'
        Ip         = $ip
        Version    = $ip.Contains(':') ? 6 : 4
        Agreed     = $votes.Count -eq 1
        Answers    = @($answers)
        Network    = $registration ? $registration.Network : $null
        Owner      = $registration ? $registration.Owner : $null
        Country    = $registration ? $registration.Country : $null
        Cidr       = $registration ? $registration.Cidr : $null
        Asn        = $registration ? $registration.Asn : $null
        RdapUrl    = $registration ? $registration.RdapUrl : $null
        Source     = $commands -join '; '
    }
}
