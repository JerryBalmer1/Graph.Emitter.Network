function Test-NetworkPath {
    <#
    .SYNOPSIS
        Tests ICMP reachability of a host: sent, received, loss and round-trip times.

    .DESCRIPTION
        Auto: the .NET path on Windows, ping on Linux. Native: ping (ping.exe -n -w on Windows,
        ping -c -W on Linux), parsed from its text output (English; on Linux it runs with
        LC_ALL=C, and output the parser cannot read is an error naming -Tool DotNet). On Windows,
        ping.exe follows the display language, and System.Net.NetworkInformation.Ping uses the
        same ICMP API, so Auto takes the .NET path there. The .NET floor sends ICMP echoes with System.Net.NetworkInformation.Ping,
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
        Auto (Windows: .NET; Linux: ping when installed, else .NET), Native, or DotNet.

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

    begin {
        # On Windows, Auto is the .NET path: System.Net.NetworkInformation.Ping calls the same ICMP
        # API as ping.exe (IcmpSendEcho2), and ping.exe prints in the Windows display language,
        # which the English parser cannot read. -Tool Native still runs ping.exe.
        $chosen = ($Tool -eq 'Auto' -and $IsWindows) ? 'DotNet' : (Resolve-NetworkGraphTool -Tool $Tool -Candidate @('ping') -CommandName 'Test-NetworkPath')
    }
    process {
        foreach ($item in $Target) {
            if ($chosen -eq 'ping') {
                $arguments = $IsWindows ? @('-n', "$Count", '-w', "$Timeout", $item) : @('-c', "$Count", '-W', "$([math]::Ceiling($Timeout / 1000))", $item)
                # Exit 1 is "no reply", an answer; anything else (2: unknown host, bad option) is
                # an error for this target only, as is output the parser does not recognise.
                try {
                    $run = Invoke-NetworkGraphNative -FilePath ping -ArgumentList $arguments -TimeoutSec ([math]::Ceiling($Count * ($Timeout / 1000 + 1)) + 10) -OkExitCodes 0, 1
                    $parsed = ConvertFrom-NetworkGraphPingOutput -Text $run.Output -ExitCode $run.ExitCode
                }
                catch { Write-Error -Message $_.Exception.Message -ErrorId 'NativeToolFailed' -Category InvalidResult -TargetObject $item; continue }
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
                $source = "[System.Net.NetworkInformation.Ping]::new() | ForEach-Object { foreach (`$i in 1..$Count) { `$_.Send('$item', $Timeout) } }"
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
