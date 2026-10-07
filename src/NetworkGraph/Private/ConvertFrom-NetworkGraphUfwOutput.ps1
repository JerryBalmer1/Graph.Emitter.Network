function ConvertFrom-NetworkGraphUfwOutput {
    # Not exported. 'ufw status' text to { State, Reason, Profiles }: 'Status: active' is Enabled,
    # 'Status: inactive' Disabled, anything else (for example the not-root error) Unknown with the
    # text as Reason. Regex, pinned by tests/fixtures/ufw.linux.txt.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    $state = 'Unknown'
    if ($Text -match '(?m)^Status:\s+active\b') { $state = 'Enabled' }
    elseif ($Text -match '(?m)^Status:\s+inactive\b') { $state = 'Disabled' }
    [pscustomobject]@{ State = $state; Reason = "ufw: $($Text.Trim())"; Profiles = @() }
}
