function Test-NetworkPath {
    <#
    .SYNOPSIS
        Tests ICMP reachability of a host: sent, received, loss and round-trip times.

    .DESCRIPTION
        Native: ping (ping.exe -n -w on Windows, ping -c -W on Linux), parsed from its text output
        (English only). The .NET floor sends ICMP echoes with System.Net.NetworkInformation.Ping,
        the same API Test-Connection uses. ICMP is often filtered: Reachable $false means no echo
        reply, not that the host is down; use Test-NetworkPort for a TCP check.

    .PARAMETER Target
        Host names or addresses. Accepts the pipeline and objects with a Target, Ip or RemoteIp
        property.

    .PARAMETER Count
        Echo requests per target. Default 4.

    .PARAMETER Timeout
        Milliseconds to wait for each reply. Default 1000. Linux ping takes whole seconds (rounded
        up).

    .PARAMETER Tool
        Auto (native when installed, else .NET), Native, or DotNet.

    .EXAMPLE
        Test-NetworkPath 1.1.1.1 -Count 2

    .OUTPUTS
        NetworkGraph.PathTest: Target, Ip, Reachable, Sent, Received, LossPercent, RttMs,
        AverageMs, Source.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.PathTest')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Ip', 'RemoteIp', 'ComputerName')]
        [string[]]
        $Target,

        [ValidateRange(1, 1000)]
        [int]
        $Count = 4,

        [ValidateRange(1, 60000)]
        [int]
        $Timeout = 1000,

        [ValidateSet('Auto', 'Native', 'DotNet')]
        [string]
        $Tool = 'Auto'
    )

    begin { $chosen = Resolve-NetworkGraphTool -Tool $Tool -Candidate @('ping') -CommandName 'Test-NetworkPath' }
    process {
        foreach ($item in $Target) {
            if ($chosen -eq 'ping') {
                $arguments = $IsWindows ? @('-n', "$Count", '-w', "$Timeout", $item) : @('-c', "$Count", '-W', "$([math]::Ceiling($Timeout / 1000))", $item)
                $run = Invoke-NetworkGraphNative -FilePath ping -ArgumentList $arguments -TimeoutSec ([math]::Ceiling($Count * ($Timeout / 1000 + 1)) + 10)
                $parsed = ConvertFrom-NetworkGraphPingOutput -Text $run.Output
                $sent = $parsed.Sent ?? $Count
                $ip = $parsed.Ip
                $rtts = $parsed.RttMs
                $source = $run.CommandLine
            }
            else {
                $ping = [System.Net.NetworkInformation.Ping]::new()
                $rtts = [System.Collections.Generic.List[double]]::new()
                $ip = $null
                try {
                    for ($i = 0; $i -lt $Count; $i++) {
                        $reply = $ping.Send($item, $Timeout)
                        if ($reply.Status -eq 'Success') { $rtts.Add($reply.RoundtripTime); $ip = $reply.Address.ToString() }
                    }
                }
                catch { Write-Error -Message "${item}: $($_.Exception.InnerException.Message ?? $_.Exception.Message)" -ErrorId 'PingFailed' -Category ResourceUnavailable -TargetObject $item }
                finally { $ping.Dispose() }
                $sent = $Count
                $rtts = $rtts.ToArray()
                $source = "[System.Net.NetworkInformation.Ping]::new().Send('$item', $Timeout) x $Count"
            }
            $received = @($rtts).Count
            [pscustomobject]@{
                PSTypeName  = 'NetworkGraph.PathTest'
                Target      = $item
                Ip          = $ip
                Reachable   = $received -gt 0
                Sent        = $sent
                Received    = $received
                LossPercent = $sent ? [math]::Round(100 * ($sent - $received) / $sent, 1) : $null
                RttMs       = @($rtts)
                AverageMs   = $received ? [math]::Round((@($rtts) | Measure-Object -Average).Average, 2) : $null
                Source      = $source
            }
        }
    }
}
