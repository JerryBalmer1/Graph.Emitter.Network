function ConvertFrom-NetworkGraphTracertOutput {
    # Not exported. Windows tracert.exe text to hop rows { Hop, Ip, Host, RttMs, LossPercent }.
    # tracert has no structured output: regex, pinned by tests/fixtures/tracert.windows.txt. Each
    # probe column is 'N ms', '<1 ms' (recorded as 0) or '*' (lost). English output only.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    foreach ($line in $Text -split "`r?`n") {
        $match = [regex]::Match($line, '^\s*(\d+)((?:\s+(?:<?\d+\s+ms|\*))+)\s+(.*?)\s*$')
        if (-not $match.Success) { continue }
        $probes = [regex]::Matches($match.Groups[2].Value, '<?\d+\s+ms|\*')
        $rtts = [System.Collections.Generic.List[double]]::new()
        $lost = 0
        foreach ($probe in $probes) {
            if ($probe.Value -eq '*') { $lost++ }
            elseif ($probe.Value.StartsWith('<')) { $rtts.Add(0) }
            else { $rtts.Add([double]($probe.Value -replace '\s*ms', '')) }
        }
        $responder = ConvertFrom-NetworkGraphHopText -Text $match.Groups[3].Value
        [pscustomobject]@{
            Hop         = [int]$match.Groups[1].Value
            Ip          = $responder.Ip
            Host        = $responder.Host
            RttMs       = $rtts.ToArray()
            LossPercent = $probes.Count ? [math]::Round(100 * $lost / $probes.Count, 1) : $null
        }
    }
}
