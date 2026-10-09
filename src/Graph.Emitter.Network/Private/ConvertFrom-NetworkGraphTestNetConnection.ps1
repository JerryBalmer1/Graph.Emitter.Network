function ConvertFrom-NetworkGraphTestNetConnection {
    # Not exported. Test-NetConnection -Port objects (live, or
    # tests/fixtures/Test-NetConnection.windows.json) to { Ip, Port, Open }. Structured.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $InputObject
    )

    foreach ($item in $InputObject) {
        $address = $item.RemoteAddress
        if ($address -isnot [string] -and $null -ne $address) { $address = $address.IPAddressToString }
        [pscustomobject]@{ Ip = [string]$address; Port = [int]$item.RemotePort; Open = [bool]$item.TcpTestSucceeded }
    }
}
