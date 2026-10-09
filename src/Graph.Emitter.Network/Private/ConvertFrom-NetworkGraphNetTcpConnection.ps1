function ConvertFrom-NetworkGraphNetTcpConnection {
    # Not exported. Get-NetTCPConnection objects (live, or the JSON fixture
    # tests/fixtures/Get-NetTCPConnection.windows.json) to connection rows. Structured: properties
    # are read by name. ProcessName is filled from -ProcessName, a pid -> name map.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $InputObject,

        [hashtable]
        $ProcessName = @{}
    )

    foreach ($item in $InputObject) {
        $processId = $item.OwningProcess
        New-NetworkGraphConnectionRow -Protocol Tcp -LocalIp (ConvertTo-NetworkGraphIpValue -Ip ([string]$item.LocalAddress) -Unmap).Ip -LocalPort $item.LocalPort `
            -RemoteIp (ConvertTo-NetworkGraphIpValue -Ip ([string]$item.RemoteAddress) -Unmap).Ip -RemotePort $item.RemotePort `
            -State ([string]$item.State) -ProcessId $processId -ProcessName $ProcessName[[int]$processId]
    }
}
