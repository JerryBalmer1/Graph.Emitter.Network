function ConvertFrom-NetworkGraphNslookupOutput {
    # Not exported. nslookup text for an A or AAAA query to DNS rows { Name, Type, Ttl, Data,
    # Section } plus the Server that answered, Windows or Linux format. nslookup has no
    # structured output: regex, pinned by tests/fixtures/nslookup.windows.txt and
    # nslookup.linux.txt. Windows lists further addresses on indented lines under 'Addresses:';
    # Linux repeats 'Name:' and 'Address:'. The Server block comes before the first 'Name:'.
    # nslookup reports no TTL.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text,

        [int]
        $ExitCode = 0
    )

    $server = $null
    $name = $null
    $collecting = $false
    $rows = @(foreach ($line in $Text -split "`r?`n") {
        if ($line -match '^Server:\s+(\S+)') { $server = $Matches[1]; continue }
        if ($line -match '^Name:\s+(\S+)') { $name = $Matches[1].TrimEnd('.'); $collecting = $false; continue }
        if (-not $name) { continue }
        $value = $null
        if ($line -match '^Address(?:es)?:\s+(\S+)') { $value = $Matches[1]; $collecting = $true }
        elseif ($collecting -and $line -match '^\s+([0-9A-Fa-f:.]+)\s*$') { $value = $Matches[1] }
        else { $collecting = $false }
        if (-not $value) { continue }
        $value = ($value -split '#')[0]
        [pscustomobject]@{
            Name    = $name
            Type    = $value.Contains(':') ? 'AAAA' : 'A'
            Ttl     = $null
            Data    = $value
            Section = 'Answer'
            Server  = $server
        }
    })
    Assert-NetworkGraphRecognised -Tool nslookup -Text $Text -ExitCode $ExitCode -Count $rows.Count -Recognised:($Text -match "can't find|No answer")
    $rows
}
