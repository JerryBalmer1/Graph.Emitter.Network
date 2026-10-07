function ConvertFrom-NetworkGraphNetFirewallProfile {
    # Not exported. Get-NetFirewallProfile objects (live, or
    # tests/fixtures/Get-NetFirewallProfile.windows.json) to { State, Reason, Profiles }: Enabled
    # when every profile is on, Disabled when none is, else Partial. Structured; Enabled is a
    # GpoBoolean whose text is True or False.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $InputObject
    )

    $profiles = @(foreach ($item in $InputObject) { [pscustomobject]@{ Profile = [string]$item.Name; Enabled = ([string]$item.Enabled -eq 'True') } })
    $on = @($profiles | Where-Object Enabled).Count
    $state = if (-not $profiles.Count) { 'Unknown' } elseif ($on -eq $profiles.Count) { 'Enabled' } elseif ($on -eq 0) { 'Disabled' } else { 'Partial' }
    [pscustomobject]@{
        State    = $state
        Reason   = $profiles.Count ? (($profiles | ForEach-Object { '{0} {1}' -f $_.Profile, ($_.Enabled ? 'on' : 'off') }) -join ', ') : 'Get-NetFirewallProfile returned no profiles.'
        Profiles = $profiles
    }
}
