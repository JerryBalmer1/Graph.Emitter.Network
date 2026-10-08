function Get-NetworkGraphInterfaceKeyMap {
    # Not exported. This host's interfaces as two lookups to InterfaceKey, the stable half of an
    # Interface node Id: ByIndex (interface index, as a string) and ByName (alias or device name),
    # plus Source, the in-process read that produced them. For tools that name an interface only by
    # index or name (Get-NetRoute, Get-NetNeighbor, arp, ip route, ip neigh, /proc/net/arp).
    # Windows: the .NET NetworkInterface Id, which is the interface GUID (Get-NetAdapter
    # InterfaceGuid), indexed by its IPv4 and IPv6 Index; it includes the loopback pseudo-interface,
    # which Get-NetAdapter and Get-NetIPConfiguration leave out. Linux: /sys/class/net/<dev>/ifindex,
    # the ifindex ip reports. Other platforms: the .NET index. -InputObject takes rows
    # { Name, Id, IPv4Index, IPv6Index } instead of reading .NET (tests/fixtures/
    # NetworkInterface.windows.json was captured in that shape); -Platform says whose rules apply.
    param(
        [object[]]
        $InputObject,

        [string]
        $Platform = $script:NetworkGraphPlatform
    )

    $byIndex = @{}
    $byName = @{}
    if ($Platform -eq 'Linux' -and -not $InputObject) {
        $directories = [System.IO.Directory]::Exists('/sys/class/net') ? [System.IO.Directory]::GetDirectories('/sys/class/net') : @()
        foreach ($directory in $directories) {
            $file = Join-Path $directory 'ifindex'
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            $index = [System.IO.File]::ReadAllText($file).Trim()
            $byIndex[$index] = $index
            $byName[(Split-Path -Leaf $directory)] = $index
        }
        return [pscustomobject]@{ ByIndex = $byIndex; ByName = $byName; Source = 'Get-Content /sys/class/net/*/ifindex' }
    }

    $rows = $InputObject
    if (-not $rows) {
        $rows = foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            $properties = $adapter.GetIPProperties()
            $v4 = try { $properties.GetIPv4Properties().Index } catch { $null }
            $v6 = try { $properties.GetIPv6Properties().Index } catch { $null }
            [pscustomobject]@{ Name = $adapter.Name; Id = $adapter.Id; IPv4Index = $v4; IPv6Index = $v6 }
        }
    }
    foreach ($row in $rows) {
        $indexes = @($row.IPv4Index, $row.IPv6Index | Where-Object { $null -ne $_ } | Select-Object -Unique)
        $key = ($Platform -eq 'Windows') ? [string]$row.Id : [string]@($indexes)[0]
        if (-not $key) { continue }
        foreach ($index in $indexes) { $byIndex["$index"] = $key }
        $byName[[string]$row.Name] = $key
    }
    [pscustomobject]@{ ByIndex = $byIndex; ByName = $byName; Source = '[System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()' }
}
