function Complete-NetworkGraphHop {
    # Not exported. Finishes the hop rows of one trace, whichever tool produced them, to
    # { Hop, Ip, Host, RttMs, AvgMs, LossPercent, Responded }. RttMs is per-probe samples only;
    # a tool that reports only an average per hop (mtr, pathping) passes it as AvgMs with RttMs
    # empty, otherwise AvgMs is the mean of the samples. Responded is $true when the hop answered
    # at least one probe. A hop that answered nothing while a later hop did gets LossPercent $null:
    # that router declines to send ICMP Time Exceeded (filtered or rate-limited) and the path
    # itself delivered, so 100 would read as loss that is not there. A hop with some answers keeps
    # its real LossPercent, and silent hops after the last answer keep theirs (usually 100).
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Hop
    )

    $rows = @($Hop | Where-Object { $null -ne $_ })
    $answered = @(foreach ($row in $rows) {
            $hasAverage = $row.PSObject.Properties['AvgMs'] -and $null -ne $row.AvgMs
            [bool]($row.Ip -or @($row.RttMs).Count -or $hasAverage)
        })
    $lastAnswered = -1
    for ($i = 0; $i -lt $rows.Count; $i++) { if ($answered[$i]) { $lastAnswered = $i } }

    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $samples = @($row.RttMs | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
        $average = ($row.PSObject.Properties['AvgMs'] -and $null -ne $row.AvgMs) ? [double]$row.AvgMs : ($samples.Count ? [math]::Round(($samples | Measure-Object -Average).Average, 3) : $null)
        [pscustomobject]@{
            Hop         = [int]$row.Hop
            Ip          = $row.Ip
            Host        = $row.Host
            RttMs       = [double[]]$samples
            AvgMs       = $average
            LossPercent = (-not $answered[$i] -and $i -lt $lastAnswered) ? $null : $row.LossPercent
            Responded   = $answered[$i]
        }
    }
}
