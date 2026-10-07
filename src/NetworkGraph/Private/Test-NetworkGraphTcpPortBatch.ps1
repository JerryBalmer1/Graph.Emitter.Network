function Test-NetworkGraphTcpPortBatch {
    # Not exported. TCP connect tests with System.Net.Sockets.TcpClient, up to -ThrottleLimit at a
    # time, each given -Timeout ms. -Pair takes { Target, Ip, Port } items (Ip already resolved).
    # Returns { Target, Ip, Port, Open, LatencyMs } per pair: Open $true on connect, $false on
    # refusal or timeout. Pure .NET; used by Test-NetworkPort (-Tool Auto and DotNet) and by
    # Invoke-NetworkScan when nmap is not installed.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Pair,

        [int]
        $Timeout = 2000,

        [int]
        $ThrottleLimit = 32
    )

    for ($start = 0; $start -lt $Pair.Count; $start += $ThrottleLimit) {
        $batch = @($Pair[$start..([math]::Min($start + $ThrottleLimit, $Pair.Count) - 1)])
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $work = @(foreach ($item in $batch) {
                $client = [System.Net.Sockets.TcpClient]::new([System.Net.IPAddress]::Parse($item.Ip).AddressFamily)
                [pscustomobject]@{
                    Item      = $item
                    Client    = $client
                    Task      = $client.ConnectAsync([System.Net.IPAddress]::Parse($item.Ip), [int]$item.Port)
                    ElapsedMs = $null
                }
            })
        # Wait for whichever finishes next and note when, until all are done or time is up.
        $pending = [System.Collections.Generic.List[object]]::new([object[]]$work)
        while ($pending.Count -and $watch.ElapsedMilliseconds -lt $Timeout) {
            $index = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]@($pending.Task), [int]($Timeout - $watch.ElapsedMilliseconds))
            if ($index -lt 0) { break }
            $pending[$index].ElapsedMs = $watch.Elapsed.TotalMilliseconds
            $pending.RemoveAt($index)
        }
        foreach ($entry in $work) {
            $open = $entry.Task.Status -eq 'RanToCompletion' -and $entry.Client.Connected
            [pscustomobject]@{
                Target    = $entry.Item.Target
                Ip        = $entry.Item.Ip
                Port      = [int]$entry.Item.Port
                Open      = $open
                LatencyMs = $open ? [math]::Round($entry.ElapsedMs, 1) : $null
            }
            $entry.Client.Dispose()
        }
    }
}
