function Get-NetworkGraphDataFileInfo {
    # Not exported. One NetworkGraph.DataFile row for a data kind: where it is read from, how big,
    # when its sources were pulled, how old that is against the file's maxAgeDays, and its
    # sources. -Path reads that file instead of the user-then-bundled one.
    param(
        [Parameter(Mandatory)]
        [string]
        $Kind,

        [string]
        $Path
    )

    $location = Get-NetworkGraphDataPath -Kind $Kind
    $where = $location.Location
    if ($Path) {
        $where = ($Path -eq $location.BundledPath) ? 'Bundled' : (($Path -eq $location.UserPath) ? 'User' : 'Path')
    }
    else {
        $Path = $location.Path
    }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            PSTypeName = 'NetworkGraph.DataFile'; Kind = $Kind; File = $location.File; Location = 'Missing'; Path = $null
            Bytes = $null; Pulled = $null; AgeDays = $null; MaxAgeDays = $null; Entries = $null; Sources = @()
        }
    }

    $document = Read-NetworkGraphDataText -Path $Path | ConvertFrom-Json -AsHashtable -Depth 64
    $sources = @(foreach ($source in @($document['sources'])) {
            [pscustomobject]@{ PSTypeName = 'NetworkGraph.DataSource'; Kind = $Kind; Url = $source['url']; Title = $source['title']; Pulled = $source['pulled'] }
        })
    $pulled = $document['pulled'] ?? (@($sources.Pulled | Sort-Object) | Select-Object -Last 1)
    $entries = switch ($Kind) {
        'CloudReservations' { $document['clouds'].Keys.Count }
        'CloudRanges' { $document['prefixes'].Keys.Count }
        'IpSources' { @($document['endpoints']).Count }
        default { ($document['entries'] -is [System.Collections.IDictionary]) ? $document['entries'].Keys.Count : @($document['entries']).Count }
    }
    $age = $null
    if ($pulled) { $age = [int]([datetime]::UtcNow.Date - [datetime]::ParseExact($pulled, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)).TotalDays }

    [pscustomobject]@{
        PSTypeName = 'NetworkGraph.DataFile'
        Kind       = $Kind
        File       = $location.File
        Location   = $where
        Path       = (Resolve-Path -LiteralPath $Path).ProviderPath
        Bytes      = (Get-Item -LiteralPath $Path).Length
        Pulled     = $pulled
        AgeDays    = $age
        MaxAgeDays = $document['maxAgeDays']
        Entries    = $entries
        Sources    = $sources
    }
}
