function Get-NetworkGraphDataDocument {
    # Not exported. One data kind parsed as an ordered hashtable, from the user cache when it holds
    # the file, else the bundled copy. Parsed once per file version and kept in memory. A missing
    # file is a terminating error naming the command that restores it.
    param(
        [Parameter(Mandatory)]
        [string]
        $Kind
    )

    $location = Get-NetworkGraphDataPath -Kind $Kind
    if (-not $location.Path) {
        $fix = ($Kind -in $script:NetworkGraphHarvestKinds) ? "Update-NetworkGraphData -Kind $Kind" : 'reinstall the module (Install-Module NetworkGraph -Force)'
        throw [System.IO.FileNotFoundException]::new("No $Kind data: neither $($location.UserPath) nor $($location.BundledPath) exists. Run $fix.")
    }

    $item = Get-Item -LiteralPath $location.Path
    $key = "$($item.FullName)|$($item.LastWriteTimeUtc.Ticks)|$($item.Length)"
    $memo = $script:NetworkGraphDataMemo[$Kind]
    if ($memo -and $memo.Key -ceq $key) { return $memo.Document }

    $document = Read-NetworkGraphDataText -Path $item.FullName | ConvertFrom-Json -AsHashtable -Depth 64
    $document['_path'] = $item.FullName
    $document['_location'] = $location.Location
    $script:NetworkGraphDataMemo[$Kind] = @{ Key = $key; Document = $document; Index = $null }
    $document
}
