function Get-NetworkGraphPortHarvest {
    # Not exported. ports.json from the IANA Service Name and Transport Protocol Port Number
    # Registry: entries maps '<port>/<tcp|udp>' to [service name, description]. The first named row
    # for a port and protocol wins (registry order); ranges are expanded; rows with no service name
    # (Reserved, Unassigned) are skipped.
    param([string]$Pulled = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))

    $url = 'https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.csv'
    $rows = (Invoke-NetworkGraphWebRequest -Uri $url -TimeoutSec 300).Content | ConvertFrom-Csv
    $entries = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $keys = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $name = ([string]$row.'Service Name').Trim()
        $protocol = ([string]$row.'Transport Protocol').Trim().ToLowerInvariant()
        $ports = ([string]$row.'Port Number').Trim()
        if (-not $name -or $protocol -notin 'tcp', 'udp' -or $ports -notmatch '^(\d+)(?:-(\d+))?$') { continue }
        $low = [int]$Matches[1]
        $high = $Matches[2] ? [int]$Matches[2] : $low
        $description = (([string]$row.Description) -replace '\s+', ' ').Trim()
        for ($port = $low; $port -le $high; $port++) {
            $key = "$port/$protocol"
            if ($entries.ContainsKey($key)) { continue }
            $entries[$key] = @($name, $description)
            $keys.Add([pscustomobject]@{ Key = $key; Port = $port; Protocol = $protocol })
        }
    }
    $ordered = [ordered]@{}
    foreach ($item in ($keys | Sort-Object Port, Protocol)) { $ordered[$item.Key] = $entries[$item.Key] }

    [ordered]@{
        formatVersion = 1
        kind          = 'Ports'
        maxAgeDays    = 365
        pulled        = $Pulled
        sources       = @([ordered]@{ url = $url; title = 'IANA Service Name and Transport Protocol Port Number Registry'; pulled = $Pulled })
        entries       = $ordered
    }
}
