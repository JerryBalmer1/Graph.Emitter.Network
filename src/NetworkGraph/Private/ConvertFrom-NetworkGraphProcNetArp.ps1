function ConvertFrom-NetworkGraphProcNetArp {
    # Not exported. Linux /proc/net/arp (the .NET floor reads the file; no tool runs) to neighbour
    # rows. Whitespace columns: IP address, HW type, Flags, HW address, Mask, Device. Flags 0x2 is
    # Complete, 0x4 adds Permanent, 0x0 is Incomplete. Pinned by tests/fixtures/proc-net-arp.linux.txt.
    # InterfaceKey: Device looked up in -KeyMap (Get-NetworkGraphInterfaceKeyMap).
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text,

        $KeyMap
    )

    foreach ($line in ($Text -split "`r?`n" | Select-Object -Skip 1)) {
        $tokens = @($line -split '\s+' | Where-Object { $_ })
        if ($tokens.Count -lt 6) { continue }
        $flags = [Convert]::ToInt32($tokens[2], 16)
        $state = if ($flags -band 4) { 'Permanent' } elseif ($flags -band 2) { 'Complete' } else { 'Incomplete' }
        New-NetworkGraphNeighborRow -Ip $tokens[0] -MacAddress $tokens[3] -State $state -Interface $tokens[5] `
            -InterfaceKey (Resolve-NetworkGraphInterfaceKey -KeyMap $KeyMap -Name $tokens[5])
    }
}
