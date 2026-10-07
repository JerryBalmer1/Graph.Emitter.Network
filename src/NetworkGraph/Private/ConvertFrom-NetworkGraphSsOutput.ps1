function ConvertFrom-NetworkGraphSsOutput {
    # Not exported. 'ss -tunap' text to connection rows (New-NetworkGraphConnectionRow). ss has no
    # JSON output in the versions distributions ship, so columns are split on whitespace (Netid,
    # State, Recv-Q, Send-Q, Local, Peer, Process) and the process is read from
    # users:(("name",pid=N,fd=N)), the first one when several share the socket. Pinned by
    # tests/fixtures/ss.linux.txt.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text,

        [int]
        $ExitCode = 0
    )

    $rows = @(foreach ($line in $Text -split "`r?`n") {
        $tokens = @($line -split '\s+' | Where-Object { $_ })
        if ($tokens.Count -lt 6 -or $tokens[0] -notin 'tcp', 'udp') { continue }
        $local = Split-NetworkGraphEndpoint -Endpoint $tokens[4]
        $peer = Split-NetworkGraphEndpoint -Endpoint $tokens[5]
        $processId = $null
        $processName = $null
        $rest = ($tokens | Select-Object -Skip 6) -join ' '
        if ($rest -match 'users:\(\("([^"]*)",pid=(\d+)') { $processName = $Matches[1]; $processId = $Matches[2] }
        New-NetworkGraphConnectionRow -Protocol ($tokens[0] -eq 'tcp' ? 'Tcp' : 'Udp') -LocalIp $local.Ip -LocalPort $local.Port `
            -RemoteIp $peer.Ip -RemotePort $peer.Port -State (ConvertTo-NetworkGraphTcpState -State $tokens[1]) -ProcessId $processId -ProcessName $processName
    })
    Assert-NetworkGraphRecognised -Tool ss -Text $Text -ExitCode $ExitCode -Count $rows.Count -Recognised:($Text -match '(?m)^Netid\s')
    $rows
}
