function ConvertFrom-NetworkGraphMtrJson {
    # Not exported. mtr --json report to hop rows { Hop, Ip, Host, RttMs, LossPercent }. Structured
    # output, no regex. RttMs is mtr's average for the hop (mtr reports aggregates, not samples);
    # a '???' host (no reply) has Ip $null and no RTT. Pinned by tests/fixtures/mtr.linux.json.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    $report = ($Text | ConvertFrom-Json -AsHashtable)['report']
    foreach ($hub in @($report['hubs'])) {
        $responder = ConvertFrom-NetworkGraphHopText -Text ([string]$hub['host'])
        $answered = $hub['host'] -ne '???'
        [pscustomobject]@{
            Hop         = [int]$hub['count']
            Ip          = $responder.Ip
            Host        = ($answered -and -not $responder.Ip) ? [string]$hub['host'] : $responder.Host
            RttMs       = $answered ? @([double]$hub['Avg']) : @()
            LossPercent = [double]$hub['Loss%']
        }
    }
}
