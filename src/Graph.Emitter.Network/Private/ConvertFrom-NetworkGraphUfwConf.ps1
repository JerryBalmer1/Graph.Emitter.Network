function ConvertFrom-NetworkGraphUfwConf {
    # Not exported. /etc/ufw/ufw.conf text to { State, Reason, Profiles }: ENABLED=yes is Enabled,
    # ENABLED=no Disabled, anything else $null (the caller falls back to 'ufw status'). Reading the
    # file needs no root, where 'ufw status' does. Pinned by tests/fixtures/ufw.conf.linux.txt.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    $state = $null
    if ($Text -match '(?m)^\s*ENABLED\s*=\s*"?(yes|no)"?\s*$') { $state = ($Matches[1] -eq 'yes') ? 'Enabled' : 'Disabled' }
    if (-not $state) { return }
    [pscustomobject]@{ State = $state; Reason = "ufw.conf ENABLED=$($Matches[1])"; Profiles = @() }
}
