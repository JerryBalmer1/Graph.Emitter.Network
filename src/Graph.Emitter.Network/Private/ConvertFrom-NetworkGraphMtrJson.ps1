function ConvertFrom-NetworkGraphMtrJson {
    # Not exported. mtr --json report to hop rows (Complete-NetworkGraphHop shape). Structured
    # output, no regex. mtr reports aggregates, not samples: its average is AvgMs and RttMs stays
    # empty; a '???' host (no reply) has Ip $null and no AvgMs. Pinned by tests/fixtures/mtr.linux.json.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    $report = ($Text | ConvertFrom-Json -AsHashtable)['report']
    $rows = foreach ($hub in @($report['hubs'])) {
        $responder = ConvertFrom-NetworkGraphHopText -Text ([string]$hub['host'])
        $answered = $hub['host'] -ne '???'
        [pscustomobject]@{
            Hop         = [int]$hub['count']
            Ip          = $responder.Ip
            Host        = ($answered -and -not $responder.Ip) ? [string]$hub['host'] : $responder.Host
            RttMs       = @()
            AvgMs       = $answered ? [double]$hub['Avg'] : $null
            LossPercent = [double]$hub['Loss%']
        }
    }
    Complete-NetworkGraphHop -Hop @($rows)
}
