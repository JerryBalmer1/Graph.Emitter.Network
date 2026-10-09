function Test-NetworkGraphTcpPortBatch {
    # Not exported. TCP connect tests with System.Net.Sockets.TcpClient, up to -ThrottleLimit at a
    # time, each given -Timeout ms. -Pair takes { Target, Ip, Port } items (Ip already resolved).
    # Returns { Target, Ip, Port, Open, LatencyMs } per pair: Open $true when the connect completed
    # within -Timeout, $false on refusal or timeout. Pure .NET; used by Test-NetworkPort (-Tool
    # Auto and DotNet) and by Invoke-NetworkScan when nmap is not installed.
    #
    # LatencyMs is per connect: each one's stopwatch reading starts after its own client is built,
    # just before ConnectAsync, so building later clients in the batch is not counted. A connect
    # that has already finished when ConnectAsync returns is timed then; the others when WaitAny
    # sees them finish. Tests set $script:NetworkGraphTcpConnector to a scriptblock taking
    # (Client, Address, Port) and returning the connect Task.
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

    $connect = $script:NetworkGraphTcpConnector ?? { param($Client, $Address, $Port) $Client.ConnectAsync($Address, $Port) }
    for ($start = 0; $start -lt $Pair.Count; $start += $ThrottleLimit) {
        $batch = @($Pair[$start..([math]::Min($start + $ThrottleLimit, $Pair.Count) - 1)])
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $work = [System.Collections.Generic.List[object]]::new()
        $pending = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $batch) {
            $address = [System.Net.IPAddress]::Parse($item.Ip)
            $client = [System.Net.Sockets.TcpClient]::new($address.AddressFamily)
            $began = $watch.Elapsed.TotalMilliseconds
            $task = & $connect $client $address ([int]$item.Port)
            $entry = [pscustomobject]@{ Item = $item; Client = $client; Task = $task; Began = $began; ElapsedMs = $null }
            if ($task.IsCompleted) { $entry.ElapsedMs = $watch.Elapsed.TotalMilliseconds - $began } else { $pending.Add($entry) }
            $work.Add($entry)
        }
        # Wait for whichever finishes next and note when, until all are done or the last one
        # started has had its -Timeout.
        $deadline = ($work | Measure-Object -Property Began -Maximum).Maximum + $Timeout
        while ($pending.Count -and $watch.Elapsed.TotalMilliseconds -lt $deadline) {
            $index = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]@($pending.Task), [int][math]::Max(1, $deadline - $watch.Elapsed.TotalMilliseconds))
            if ($index -lt 0) { break }
            $pending[$index].ElapsedMs = $watch.Elapsed.TotalMilliseconds - $pending[$index].Began
            $pending.RemoveAt($index)
        }
        foreach ($entry in $work) {
            $open = $entry.Task.Status -eq 'RanToCompletion' -and $null -ne $entry.ElapsedMs -and $entry.ElapsedMs -le $Timeout
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
