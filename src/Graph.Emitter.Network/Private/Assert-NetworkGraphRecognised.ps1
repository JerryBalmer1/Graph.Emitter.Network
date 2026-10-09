function Assert-NetworkGraphRecognised {
    # Not exported. The guard every text parser calls after parsing: exit code 0, non-empty output
    # and zero rows means the parser did not recognise the output, most often because the tool
    # printed it in another language (the parsers read English; ping.exe, tracert, pathping and
    # arp follow the Windows display language). Throws rather than return an empty or 'down'
    # answer. -Recognised marks output the parser knows to be a genuine empty answer (an ss header
    # with no sockets, nslookup's "can't find"). A non-zero exit the caller declared OK (ping 1 =
    # no reply) is an answer, not a parse failure.
    param(
        [Parameter(Mandatory)]
        [string]
        $Tool,

        [AllowEmptyString()]
        [string]
        $Text,

        [int]
        $ExitCode = 0,

        [int]
        $Count = 0,

        [switch]
        $Recognised
    )

    if ($Count -gt 0 -or $Recognised -or $ExitCode -ne 0 -or -not "$Text".Trim()) { return }
    throw [System.FormatException]::new("$Tool output not recognised (non-English locale?); use -Tool DotNet. First line: $(@("$Text".Trim() -split "`r?`n")[0])")
}
