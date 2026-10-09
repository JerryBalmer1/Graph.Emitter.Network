function Get-NetworkGraphDotNetTrace {
    # Not exported. The .NET floor for Trace-NetworkPath: TTL-stepped
    # System.Net.NetworkInformation.Ping. For TTL 1..MaxHops, -Queries echoes with that TTL; a
    # TtlExpired reply names the hop, a Success reply is the target and ends the trace. RTT is
    # measured with a stopwatch, since some platforms report 0 for TtlExpired replies. Returns hop
    # rows in the Complete-NetworkGraphHop shape.
    param(
        [Parameter(Mandatory)]
        [string]
        $Target,

        [int]
        $MaxHops = 30,

        [int]
        $Timeout = 1000,

        [int]
        $Queries = 3
    )

    $ping = [System.Net.NetworkInformation.Ping]::new()
    $buffer = [byte[]]::new(32)
    $watch = [System.Diagnostics.Stopwatch]::new()
    $rows = [System.Collections.Generic.List[object]]::new()
    try {
        for ($ttl = 1; $ttl -le $MaxHops; $ttl++) {
            $options = [System.Net.NetworkInformation.PingOptions]::new($ttl, $true)
            $rtts = [System.Collections.Generic.List[double]]::new()
            $ip = $null
            $reached = $false
            for ($q = 0; $q -lt $Queries; $q++) {
                $watch.Restart()
                $reply = $ping.Send($Target, $Timeout, $buffer, $options)
                $watch.Stop()
                if ($reply.Status -in 'TtlExpired', 'TimeExceeded', 'Success') {
                    $rtts.Add([math]::Round(($reply.Status -eq 'Success' -and $reply.RoundtripTime) ? $reply.RoundtripTime : $watch.Elapsed.TotalMilliseconds, 3))
                    if (-not $ip) { $ip = $reply.Address.ToString() }
                    if ($reply.Status -eq 'Success') { $reached = $true }
                }
            }
            $rows.Add([pscustomobject]@{
                Hop         = $ttl
                Ip          = $ip
                Host        = $null
                RttMs       = $rtts.ToArray()
                LossPercent = [math]::Round(100 * ($Queries - $rtts.Count) / $Queries, 1)
            })
            if ($reached) { break }
        }
    }
    finally {
        $ping.Dispose()
    }
    Complete-NetworkGraphHop -Hop $rows.ToArray()
}
