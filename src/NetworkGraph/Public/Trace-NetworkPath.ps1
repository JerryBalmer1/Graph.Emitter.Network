function Trace-NetworkPath {
    <#
    .SYNOPSIS
        Traces the route to a host: one row per hop with its address, round-trip times and loss.

    .DESCRIPTION
        Native: tracert (or pathping with -NativeTool pathping, slower but with per-hop loss) on
        Windows; mtr --json (structured) or traceroute on Linux, whichever is installed first in
        that order. Names are not resolved (tracert -d, traceroute -n, mtr -n). Text output is
        parsed with regex pinned by fixture tests, English only.

        The .NET floor sends TTL-stepped ICMP echoes with System.Net.NetworkInformation.Ping. A hop
        that drops ICMP shows Ip $null and LossPercent 100 with every tool.

    .PARAMETER Target
        Host name or address.

    .PARAMETER MaxHops
        Default 30.

    .PARAMETER Timeout
        Milliseconds to wait at each probe. Default 1000.

    .PARAMETER Queries
        Probes per hop. Default 3 (pathping always uses its own count).

    .PARAMETER Tool
        Auto (native when installed, else .NET), Native, or DotNet.

    .PARAMETER NativeTool
        tracert, pathping, traceroute or mtr: which native tool -Tool Native or Auto uses.

    .EXAMPLE
        Trace-NetworkPath 1.1.1.1 -Tool DotNet

    .OUTPUTS
        NetworkGraph.Hop: Target, Hop, Ip, Host, RttMs, LossPercent, Source.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.Hop')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('Ip', 'RemoteIp')]
        [string]
        $Target,

        [ValidateRange(1, 255)]
        [int]
        $MaxHops = 30,

        [ValidateRange(1, 60000)]
        [int]
        $Timeout = 1000,

        [ValidateRange(1, 10)]
        [int]
        $Queries = 3,

        [ValidateSet('Auto', 'Native', 'DotNet')]
        [string]
        $Tool = 'Auto',

        [ValidateSet('tracert', 'pathping', 'traceroute', 'mtr')]
        [string]
        $NativeTool
    )

    process {
        $candidates = $NativeTool ? @($NativeTool) : ($IsWindows ? @('tracert') : @('mtr', 'traceroute'))
        $chosen = Resolve-NetworkGraphTool -Tool $Tool -Candidate $candidates -CommandName 'Trace-NetworkPath'
        $seconds = [math]::Max(1, [math]::Ceiling($Timeout / 1000))
        $limit = $MaxHops * $Queries * $seconds + 30

        $hops = switch ($chosen) {
            'tracert' {
                $run = Invoke-NetworkGraphNative -FilePath tracert -ArgumentList '-d', '-h', "$MaxHops", '-w', "$Timeout", $Target -TimeoutSec $limit
                ConvertFrom-NetworkGraphTracertOutput -Text $run.Output
            }
            'pathping' {
                $run = Invoke-NetworkGraphNative -FilePath pathping -ArgumentList '-n', '-h', "$MaxHops", '-w', "$Timeout", '-q', "$Queries", $Target -TimeoutSec ($limit * 2 + 120)
                ConvertFrom-NetworkGraphPathpingOutput -Text $run.Output
            }
            'mtr' {
                $run = Invoke-NetworkGraphNative -FilePath mtr -ArgumentList '--json', '-n', '-c', "$Queries", '-m', "$MaxHops", $Target -TimeoutSec $limit
                ConvertFrom-NetworkGraphMtrJson -Text $run.Output
            }
            'traceroute' {
                $run = Invoke-NetworkGraphNative -FilePath traceroute -ArgumentList '-n', '-q', "$Queries", '-w', "$seconds", '-m', "$MaxHops", $Target -TimeoutSec $limit
                ConvertFrom-NetworkGraphTracerouteOutput -Text $run.Output
            }
            'DotNet' {
                $run = [pscustomobject]@{ CommandLine = "[System.Net.NetworkInformation.Ping]::new().Send('$Target', $Timeout, buffer, [PingOptions]::new(ttl, `$true)) for ttl 1..$MaxHops x $Queries" }
                Get-NetworkGraphDotNetTrace -Target $Target -MaxHops $MaxHops -Timeout $Timeout -Queries $Queries
            }
        }

        foreach ($hop in $hops) {
            [pscustomobject]@{
                PSTypeName  = 'NetworkGraph.Hop'
                Target      = $Target
                Hop         = $hop.Hop
                Ip          = $hop.Ip
                Host        = $hop.Host
                RttMs       = @($hop.RttMs)
                LossPercent = $hop.LossPercent
                Source      = $run.CommandLine
            }
        }
    }
}
