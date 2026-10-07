function Get-NetworkGraphOuiHarvest {
    # Not exported. oui.json from the IEEE MA-L (24-bit OUI) public listing: entries maps the six
    # upper-case hex digits of the assignment to the organization name. MA-M and MA-S (28- and
    # 36-bit) blocks are not included.
    param([string]$Pulled = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))

    $url = 'https://standards-oui.ieee.org/oui/oui.csv'
    $rows = (Invoke-NetworkGraphWebRequest -Uri $url -TimeoutSec 300).Content | ConvertFrom-Csv
    $entries = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($row in $rows) {
        $key = ([string]$row.Assignment).Trim().ToUpperInvariant()
        if ($key -notmatch '^[0-9A-F]{6}$' -or $entries.ContainsKey($key)) { continue }
        $entries[$key] = (([string]$row.'Organization Name') -replace '\s+', ' ').Trim()
    }
    $ordered = [ordered]@{}
    foreach ($pair in $entries.GetEnumerator()) { $ordered[$pair.Key] = $pair.Value }

    [ordered]@{
        formatVersion = 1
        kind          = 'Oui'
        maxAgeDays    = 180
        pulled        = $Pulled
        sources       = @([ordered]@{ url = $url; title = 'IEEE Registration Authority MA-L (OUI) public listing'; pulled = $Pulled })
        entries       = $ordered
    }
}
