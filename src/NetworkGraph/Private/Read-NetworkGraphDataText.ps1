function Read-NetworkGraphDataText {
    # Not exported. The UTF-8 text of one data file; a .gz file is decompressed.
    param(
        [Parameter(Mandatory)]
        [string]
        $Path
    )

    if (-not $Path.EndsWith('.gz', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    }
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $gzip = [System.IO.Compression.GZipStream]::new($stream, [System.IO.Compression.CompressionMode]::Decompress)
        $reader = [System.IO.StreamReader]::new($gzip, [System.Text.Encoding]::UTF8)
        try { $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    finally {
        $stream.Dispose()
    }
}
