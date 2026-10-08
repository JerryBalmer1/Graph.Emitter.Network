function ConvertFrom-NetworkGraphArpOutput {
    # Not exported. 'arp -a' text to neighbour rows, Windows or Linux (net-tools) format. arp has no
    # structured output, so this is regex, pinned by tests/fixtures/arp.windows.txt and
    # arp.linux.txt. Windows: an 'Interface: <ip> --- 0x<index>' header, then 'ip mac type' rows
    # (Type dynamic or static is the State; Interface is the header's address, and the header's
    # index is looked up in -KeyMap for InterfaceKey). Linux: '? (ip) at mac [ether] on dev', or
    # 'at <incomplete>'; no state; dev is looked up in -KeyMap.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text,

        [int]
        $ExitCode = 0,

        $KeyMap
    )

    $interface = $null
    $key = $null
    $rows = @(foreach ($line in $Text -split "`r?`n") {
        if ($line -match '^Interface:\s+(\S+)\s+---\s+0x([0-9a-fA-F]+)') {
            $interface = $Matches[1]
            $key = Resolve-NetworkGraphInterfaceKey -KeyMap $KeyMap -Index ([Convert]::ToInt32($Matches[2], 16))
            continue
        }
        if ($line -match '^\s+(\d+(?:\.\d+){3})\s+([0-9a-fA-F]{2}(?:-[0-9a-fA-F]{2}){5})\s+(\w+)\s*$') {
            New-NetworkGraphNeighborRow -Ip $Matches[1] -MacAddress $Matches[2] -State $Matches[3] -Interface $interface -InterfaceKey $key
            continue
        }
        if ($line -match '^\S+ \(([0-9a-fA-F:.]+)\) at (\S+)(?: \[\w+\])?(?: \w+)* on (\S+)') {
            $mac = $Matches[2]
            New-NetworkGraphNeighborRow -Ip $Matches[1] -MacAddress (($mac -eq '<incomplete>') ? $null : $mac) -State (($mac -eq '<incomplete>') ? 'Incomplete' : $null) -Interface $Matches[3] `
                -InterfaceKey (Resolve-NetworkGraphInterfaceKey -KeyMap $KeyMap -Name $Matches[3])
        }
    })
    Assert-NetworkGraphRecognised -Tool arp -Text $Text -ExitCode $ExitCode -Count $rows.Count
    $rows
}
