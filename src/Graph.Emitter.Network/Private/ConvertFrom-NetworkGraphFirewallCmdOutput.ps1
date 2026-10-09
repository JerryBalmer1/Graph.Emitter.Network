function ConvertFrom-NetworkGraphFirewallCmdOutput {
    # Not exported. 'firewall-cmd --state' text to { State, Reason, Profiles }: 'running' is
    # Enabled, 'not running' Disabled, anything else (no D-Bus, not root) Unknown with the text as
    # Reason. Pinned by tests/fixtures/firewall-cmd.linux.txt (a container with no D-Bus).
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    $text = $Text.Trim()
    $state = switch ($text) { 'running' { 'Enabled' } 'not running' { 'Disabled' } default { 'Unknown' } }
    [pscustomobject]@{ State = $state; Reason = "firewalld: $text"; Profiles = @() }
}
