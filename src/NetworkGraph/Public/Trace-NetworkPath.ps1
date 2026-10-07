function Trace-NetworkPath {
    <#
    .SYNOPSIS
        Traces the route to a host: one row per hop with its address, round-trip times and loss.

    .DESCRIPTION
        Auto: the .NET path on Windows (unless -NativeTool names a tool); on Linux mtr --json
        (structured) or traceroute, whichever is installed first in that order, else .NET.
        Native: tracert (or pathping with -NativeTool pathping, slower but with per-hop loss) on
        Windows; mtr or traceroute on Linux. Names are not resolved (tracert -d, traceroute -n,
        mtr -n). Text output is parsed with regex pinned by fixture tests, in English: tracert and
        pathping follow the Windows display language (hence .NET for Auto there), Linux tools run
        with LC_ALL=C, and output a parser cannot read is an error naming -Tool DotNet.

        The .NET floor sends TTL-stepped ICMP echoes with System.Net.NetworkInformation.Ping.

        RttMs is per-probe samples; AvgMs their mean, or the tool's own average where it reports
        only that (mtr, pathping, whose RttMs is then empty). Responded is $false for a hop that
        answered no probe. Such a hop has LossPercent $null when a later hop answered: the router
        declines to send ICMP Time Exceeded and the path delivered, so it is not loss. A hop with
        some answers keeps its real LossPercent; silent hops at the end of a trace keep 100.

    .PARAMETER Target
        Host name or address.

    .PARAMETER MaxHops
        Default 30.

    .PARAMETER Timeout
        Milliseconds to wait at each probe. Default 1000.

    .PARAMETER Queries
        Probes per hop. Default 3 (pathping always uses its own count).

    .PARAMETER Tool
        Auto (Windows: .NET unless -NativeTool is given; Linux: mtr or traceroute when installed,
        else .NET), Native, or DotNet.

    .PARAMETER NativeTool
        tracert, pathping, traceroute or mtr: which native tool -Tool Native or Auto uses.

    .EXAMPLE
        Trace-NetworkPath 1.1.1.1 -Tool DotNet

    .OUTPUTS
        NetworkGraph.Hop: Target, Tool, Hop, Ip, Host, RttMs, AvgMs, LossPercent, Responded,
        Source. Tool is tracert, pathping, mtr, traceroute or DotNet.
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
        # On Windows, Auto without -NativeTool is the .NET path: tracert and pathping print in the
        # Windows display language, which the English parsers cannot read, and the TTL-stepped
        # System.Net.NetworkInformation.Ping uses the same ICMP API. -Tool Native or -NativeTool
        # still runs them by name.
        $candidates = $NativeTool ? @($NativeTool) : ($IsWindows ? @('tracert') : @('mtr', 'traceroute'))
        $chosen = ($Tool -eq 'Auto' -and $IsWindows -and -not $NativeTool) ? 'DotNet' : (Resolve-NetworkGraphTool -Tool $Tool -Candidate $candidates -CommandName 'Trace-NetworkPath')
        $seconds = [math]::Max(1, [math]::Ceiling($Timeout / 1000))
        $limit = $MaxHops * $Queries * $seconds + 30

        $hops = switch ($chosen) {
            'tracert' {
                $run = Invoke-NetworkGraphNative -FilePath tracert -ArgumentList '-d', '-h', "$MaxHops", '-w', "$Timeout", $Target -TimeoutSec $limit -OkExitCodes 0
                ConvertFrom-NetworkGraphTracertOutput -Text $run.Output -ExitCode $run.ExitCode
            }
            'pathping' {
                $run = Invoke-NetworkGraphNative -FilePath pathping -ArgumentList '-n', '-h', "$MaxHops", '-w', "$Timeout", '-q', "$Queries", $Target -TimeoutSec ($limit * 2 + 120) -OkExitCodes 0
                ConvertFrom-NetworkGraphPathpingOutput -Text $run.Output -ExitCode $run.ExitCode
            }
            'mtr' {
                $run = Invoke-NetworkGraphNative -FilePath mtr -ArgumentList '--json', '-n', '-c', "$Queries", '-m', "$MaxHops", $Target -TimeoutSec $limit -OkExitCodes 0
                ConvertFrom-NetworkGraphMtrJson -Text $run.Output
            }
            'traceroute' {
                $run = Invoke-NetworkGraphNative -FilePath traceroute -ArgumentList '-n', '-q', "$Queries", '-w', "$seconds", '-m', "$MaxHops", $Target -TimeoutSec $limit -OkExitCodes 0
                ConvertFrom-NetworkGraphTracerouteOutput -Text $run.Output -ExitCode $run.ExitCode
            }
            'DotNet' {
                $run = [pscustomobject]@{ CommandLine = "[System.Net.NetworkInformation.Ping]::new() | ForEach-Object { foreach (`$ttl in 1..$MaxHops) { foreach (`$q in 1..$Queries) { `$_.Send('$Target', $Timeout, [byte[]]::new(32), [System.Net.NetworkInformation.PingOptions]::new(`$ttl, `$true)) } } }  # stops at the first Success" }
                Get-NetworkGraphDotNetTrace -Target $Target -MaxHops $MaxHops -Timeout $Timeout -Queries $Queries
            }
        }

        foreach ($hop in $hops) {
            [pscustomobject]@{
                PSTypeName  = 'NetworkGraph.Hop'
                Target      = $Target
                Tool        = $chosen
                Hop         = $hop.Hop
                Ip          = $hop.Ip
                Host        = $hop.Host
                RttMs       = @($hop.RttMs)
                AvgMs       = $hop.AvgMs
                LossPercent = $hop.LossPercent
                Responded   = $hop.Responded
                Source      = $run.CommandLine
            }
        }
    }
}
