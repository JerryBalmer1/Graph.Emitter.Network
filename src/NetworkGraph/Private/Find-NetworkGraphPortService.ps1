function Find-NetworkGraphPortService {
    # Not exported. The IANA service name for a port and protocol from ports.json, or $null.
    # A missing ports.json gives $null with one verbose line instead of an error, so observe
    # commands still work without it.
    param(
        [Parameter(Mandatory)]
        [int]
        $Port,

        [ValidateSet('Tcp', 'Udp')]
        [string]
        $Protocol = 'Tcp'
    )

    try { $document = Get-NetworkGraphDataDocument -Kind Ports }
    catch { Write-Verbose $_.Exception.Message; return $null }
    $row = $document['entries']["$Port/$($Protocol.ToLowerInvariant())"]
    $row ? [string]@($row)[0] : $null
}
