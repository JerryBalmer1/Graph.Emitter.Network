function ConvertFrom-NetworkGraphNcOutput {
    # Not exported. OpenBSD netcat 'nc -zv' text (stderr) to { Ip, Port, Open }: 'Connection to
    # <host> <port> port [...] succeeded!' is open; 'connect to <host> port <port> (...) failed'
    # is closed. Regex, pinned by tests/fixtures/nc.linux.txt. The exit code is the authority;
    # this reads which port each line was about.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    foreach ($line in $Text -split "`r?`n") {
        if ($line -match '^Connection to (\S+) (\d+) port .* succeeded') {
            [pscustomobject]@{ Ip = $Matches[1]; Port = [int]$Matches[2]; Open = $true }
        }
        elseif ($line -match 'connect to (\S+) port (\d+) \(\w+\) failed') {
            [pscustomobject]@{ Ip = $Matches[1]; Port = [int]$Matches[2]; Open = $false }
        }
    }
}
