function ConvertFrom-NetworkGraphNetUdpEndpoint {
    # Not exported. Get-NetUDPEndpoint objects (live, or tests/fixtures/Get-NetUDPEndpoint.windows.json)
    # to connection rows: Protocol Udp, no peer, no state. Structured.
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
        New-NetworkGraphConnectionRow -Protocol Udp -LocalIp (ConvertTo-NetworkGraphIpValue -Ip ([string]$item.LocalAddress) -Unmap).Ip -LocalPort $item.LocalPort `
            -ProcessId $processId -ProcessName $ProcessName[[int]$processId]
    }
}
