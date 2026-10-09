function Resolve-NetworkGraphReverseName {
    # Not exported. Reverse DNS for many addresses at once through System.Net.Dns, all lookups
    # started together and given -TimeoutMs in total. Returns a hashtable ip -> name; an address
    # with no PTR record, or one that did not answer in time, is absent.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]
        $Ip,

        [int]
        $TimeoutMs = 3000
    )

    $names = @{}
    $tasks = @{}
    foreach ($address in ($Ip | Where-Object { $_ } | Select-Object -Unique)) {
        $tasks[$address] = [System.Net.Dns]::GetHostEntryAsync([System.Net.IPAddress]::Parse($address))
    }
    if (-not $tasks.Count) { return $names }
    $all = [System.Threading.Tasks.Task[]]@($tasks.Values)
    try { $null = [System.Threading.Tasks.Task]::WaitAll($all, $TimeoutMs) } catch { Write-Verbose $_.Exception.Message }
    foreach ($address in $tasks.Keys) {
        $task = $tasks[$address]
        if ($task.Status -eq 'RanToCompletion' -and $task.Result.HostName -and $task.Result.HostName -ne $address) {
            $names[$address] = $task.Result.HostName
        }
    }
    $names
}
