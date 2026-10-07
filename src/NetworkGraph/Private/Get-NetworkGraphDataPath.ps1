function Get-NetworkGraphDataPath {
    # Not exported. Where one data kind is read from: the user cache when it holds the file,
    # else the bundled copy. { Kind, File, Path, Location User|Bundled|Missing, UserPath, BundledPath }.
    param(
        [Parameter(Mandatory)]
        [string]
        $Kind
    )

    $file = $script:NetworkGraphDataKinds[$Kind]
    if (-not $file) { throw [System.ArgumentException]::new("Unknown data kind '$Kind'. Kinds: $($script:NetworkGraphDataKinds.Keys -join ', ').") }
    $user = Join-Path $script:NetworkGraphDataUserRoot $file
    $bundled = Join-Path $script:NetworkGraphDataBundledRoot $file
    $path, $location = if (Test-Path -LiteralPath $user -PathType Leaf) { $user, 'User' }
    elseif (Test-Path -LiteralPath $bundled -PathType Leaf) { $bundled, 'Bundled' }
    else { $null, 'Missing' }

    [pscustomobject]@{
        Kind        = $Kind
        File        = $file
        Path        = $path
        Location    = $location
        UserPath    = $user
        BundledPath = $bundled
    }
}
