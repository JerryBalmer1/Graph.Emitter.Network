function New-NetworkGraphConnectionRow {
    # Not exported. One parsed connection { Protocol, LocalIp, LocalPort, RemoteIp, RemotePort,
    # State, ProcessId, ProcessName }, the shape every connection parser returns. A listener, or
    # a UDP socket with no peer, has RemoteIp and RemotePort $null whatever placeholder the tool
    # printed (0.0.0.0:0, [::]:0, 0.0.0.0:*).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; changes no state.')]
    param(
        [string]$Protocol,
        [string]$LocalIp,
        $LocalPort,
        [string]$RemoteIp,
        $RemotePort,
        [string]$State,
        $ProcessId,
        [string]$ProcessName
    )

    $noPeer = $State -eq 'Listen' -or $State -eq 'Bound' -or
        ((-not $RemotePort -or [int]$RemotePort -eq 0) -and ($RemoteIp -in $null, '', '0.0.0.0', '::', '*'))
    [pscustomobject]@{
        Protocol    = $Protocol
        LocalIp     = $LocalIp
        LocalPort   = ($null -ne $LocalPort) ? [int]$LocalPort : $null
        RemoteIp    = $noPeer ? $null : $RemoteIp
        RemotePort  = ($noPeer -or $null -eq $RemotePort) ? $null : [int]$RemotePort
        State       = $State ? $State : $null
        ProcessId   = ($null -ne $ProcessId -and "$ProcessId" -ne '') ? [int]$ProcessId : $null
        ProcessName = $ProcessName ? $ProcessName : $null
    }
}
