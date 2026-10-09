function ConvertFrom-NetworkGraphDigOutput {
    # Not exported. 'dig +noall +answer' text to DNS rows { Name, Type, Ttl, Data, Section }.
    # Each answer line is whitespace columns: name, TTL, class, type, data (the rest, as dig
    # prints it: '10 smtp.google.com.' for MX). Trailing dots are dropped from names. Pinned by
    # tests/fixtures/dig.linux.txt.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text,

        [int]
        $ExitCode = 0
    )

    $rows = @(foreach ($line in $Text -split "`r?`n") {
        if (-not $line.Trim() -or $line.TrimStart().StartsWith(';')) { continue }
        $tokens = @($line -split '\s+' | Where-Object { $_ })
        if ($tokens.Count -lt 5 -or $tokens[1] -notmatch '^\d+$') { continue }
        $data = ($tokens | Select-Object -Skip 4) -join ' '
        if ($tokens[3] -ne 'TXT') { $data = ($data -split ' ' | ForEach-Object { $_.TrimEnd('.') }) -join ' ' }
        [pscustomobject]@{
            Name    = $tokens[0].TrimEnd('.')
            Type    = $tokens[3]
            Ttl     = [int]$tokens[1]
            Data    = $data
            Section = 'Answer'
        }
    })
    Assert-NetworkGraphRecognised -Tool dig -Text $Text -ExitCode $ExitCode -Count $rows.Count
    $rows
}
