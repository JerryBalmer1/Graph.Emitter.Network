function ConvertFrom-NetworkGraphTracerouteOutput {
    # Not exported. Linux traceroute text (run with -n) to hop rows (Complete-NetworkGraphHop
    # shape). traceroute has no structured output: tokens are read in order, an address
    # sets the responder (the first one wins), 'N ms' is a probe time, '*' a lost probe; !H-style
    # annotations are ignored. Pinned by tests/fixtures/traceroute*.linux.txt.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text,

        [int]
        $ExitCode = 0
    )

    $rows = foreach ($line in $Text -split "`r?`n") {
        if ($line -notmatch '^\s*(\d+)\s+(.*)$') { continue }
        $hop = [int]$Matches[1]
        $tokens = $Matches[2] -split '\s+' | Where-Object { $_ }
        $ip = $null
        $hostName = $null
        $rtts = [System.Collections.Generic.List[double]]::new()
        $lost = 0
        for ($i = 0; $i -lt $tokens.Count; $i++) {
            $token = $tokens[$i]
            if ($token -eq '*') { $lost++; continue }
            if ($token -match '^[\d.]+$' -and $i + 1 -lt $tokens.Count -and $tokens[$i + 1] -eq 'ms') { $rtts.Add([double]$token); $i++; continue }
            if ($token -match '^\(([0-9A-Fa-f:.]+)\)$') { if (-not $ip) { $ip = $Matches[1] }; continue }
            $responder = ConvertFrom-NetworkGraphHopText -Text $token
            if ($responder.Ip) { if (-not $ip) { $ip = $responder.Ip }; continue }
            if ($token -notmatch '^!' -and -not $hostName -and -not $ip) { $hostName = $token }
        }
        $probes = $rtts.Count + $lost
        [pscustomobject]@{
            Hop         = $hop
            Ip          = $ip
            Host        = $hostName
            RttMs       = $rtts.ToArray()
            LossPercent = $probes ? [math]::Round(100 * $lost / $probes, 1) : $null
        }
    }
    Assert-NetworkGraphRecognised -Tool traceroute -Text $Text -ExitCode $ExitCode -Count @($rows).Count
    Complete-NetworkGraphHop -Hop @($rows)
}
