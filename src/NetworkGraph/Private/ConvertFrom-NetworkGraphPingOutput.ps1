function ConvertFrom-NetworkGraphPingOutput {
    # Not exported. Windows ping.exe or Linux iputils ping text to { Ip, Sent, Received, RttMs }.
    # ping offers no structured output, so this is regex, pinned by tests/fixtures/ping*.windows.txt
    # and ping*.linux.txt. Received counts reply lines that carry a time, so a Windows
    # 'Destination host unreachable' reply is not counted. 'time<1ms' is recorded as 0. English
    # output only.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text,

        [int]
        $ExitCode = 0
    )

    $ip = $null
    $sent = $null
    $rtts = [System.Collections.Generic.List[double]]::new()
    foreach ($line in $Text -split "`r?`n") {
        if ($line -match '^Pinging \S+ \[([^\]]+)\]' -or $line -match '^Pinging (\S+) with') { $ip = $Matches[1] }
        elseif ($line -match '^PING \S+ \(([^)]+)\)') { $ip = $Matches[1] }
        elseif ($line -match '^Reply from .*time([=<])([\d.]+)\s*ms') { $rtts.Add((($Matches[1] -eq '<') ? 0 : [double]$Matches[2])) }
        elseif ($line -match '^\d+ bytes from .*time=([\d.]+)\s*ms') { $rtts.Add([double]$Matches[1]) }
        elseif ($line -match 'Packets: Sent = (\d+)') { $sent = [int]$Matches[1] }
        elseif ($line -match '^(\d+) packets transmitted') { $sent = [int]$Matches[1] }
    }

    Assert-NetworkGraphRecognised -Tool ping -Text $Text -ExitCode $ExitCode -Count (($null -ne $sent -or $rtts.Count) ? 1 : 0)
    [pscustomobject]@{
        Ip       = $ip
        Sent     = $sent
        Received = $rtts.Count
        RttMs    = $rtts.ToArray()
    }
}
