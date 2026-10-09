function ConvertFrom-NetworkGraphPathpingOutput {
    # Not exported. Windows pathping.exe text to hop rows (Complete-NetworkGraphHop shape) from
    # its statistics table: pathping reports one averaged RTT per hop, which is AvgMs (RttMs stays
    # empty: no per-probe samples), and LossPercent is the 'Source to Here' percentage. Hop 0 (this host) is skipped. Regex, pinned by
    # tests/fixtures/pathping.windows.txt. English output only.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text,

        [int]
        $ExitCode = 0
    )

    $inTable = $false
    $rows = foreach ($line in $Text -split "`r?`n") {
        if ($line -match '^Hop\s+RTT') { $inTable = $true; continue }
        if (-not $inTable) { continue }
        $match = [regex]::Match($line, '^\s*(\d+)\s+(\d+ms|---)\s+\d+/\s*\d+\s*=\s*(\d+)%\s+\d+/\s*\d+\s*=\s*\d+%\s+(.+?)\s*$')
        if (-not $match.Success) { continue }
        $responder = ConvertFrom-NetworkGraphHopText -Text $match.Groups[4].Value
        $rtt = $match.Groups[2].Value
        [pscustomobject]@{
            Hop         = [int]$match.Groups[1].Value
            Ip          = $responder.Ip
            Host        = $responder.Host
            RttMs       = @()
            AvgMs       = ($rtt -eq '---') ? $null : [double]($rtt -replace 'ms', '')
            LossPercent = [double]$match.Groups[3].Value
        }
    }
    Assert-NetworkGraphRecognised -Tool pathping -Text $Text -ExitCode $ExitCode -Count @($rows).Count
    Complete-NetworkGraphHop -Hop @($rows)
}
