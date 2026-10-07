function Write-NetworkGraphDataFile {
    # Not exported. Writes one data document atomically (temp file, then move). Top-level values
    # are compact JSON on one line each; a list or map with more than 20 members puts one member per
    # line so a refresh diffs line by line. A .gz path is gzip-compressed. Returns the FileInfo.
    param(
        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Document
    )

    $toJson = { param($Value) ConvertTo-Json -InputObject $Value -Depth 32 -Compress }
    $builder = [System.Text.StringBuilder]::new()
    $null = $builder.Append("{`n")
    $keys = @($Document.Keys | Where-Object { -not ([string]$_).StartsWith('_') })
    for ($k = 0; $k -lt $keys.Count; $k++) {
        $name = [string]$keys[$k]
        $value = $Document[$name]
        $null = $builder.Append('  ').Append((& $toJson $name)).Append(': ')
        if ($value -is [System.Collections.IDictionary] -and $value.Count -gt 20) {
            $null = $builder.Append("{`n")
            $inner = @($value.Keys)
            for ($i = 0; $i -lt $inner.Count; $i++) {
                $null = $builder.Append('    ').Append((& $toJson ([string]$inner[$i]))).Append(': ').Append((& $toJson $value[$inner[$i]]))
                $null = $builder.Append(($i -lt $inner.Count - 1) ? ",`n" : "`n")
            }
            $null = $builder.Append('  }')
        }
        elseif ($value -is [System.Collections.IList] -and $value.Count -gt 20) {
            $null = $builder.Append("[`n")
            for ($i = 0; $i -lt $value.Count; $i++) {
                $null = $builder.Append('    ').Append((& $toJson $value[$i]))
                $null = $builder.Append(($i -lt $value.Count - 1) ? ",`n" : "`n")
            }
            $null = $builder.Append('  ]')
        }
        else {
            $null = $builder.Append((& $toJson $value))
        }
        $null = $builder.Append(($k -lt $keys.Count - 1) ? ",`n" : "`n")
    }
    $null = $builder.Append("}`n")

    $folder = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
    $temp = "$Path.tmp"
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($builder.ToString())
    if ($Path.EndsWith('.gz', [System.StringComparison]::OrdinalIgnoreCase)) {
        $stream = [System.IO.File]::Create($temp)
        try {
            $gzip = [System.IO.Compression.GZipStream]::new($stream, [System.IO.Compression.CompressionLevel]::Optimal)
            try { $gzip.Write($bytes, 0, $bytes.Length) } finally { $gzip.Dispose() }
        }
        finally {
            $stream.Dispose()
        }
    }
    else {
        [System.IO.File]::WriteAllBytes($temp, $bytes)
    }
    Move-Item -LiteralPath $temp -Destination $Path -Force
    Get-Item -LiteralPath $Path
}
