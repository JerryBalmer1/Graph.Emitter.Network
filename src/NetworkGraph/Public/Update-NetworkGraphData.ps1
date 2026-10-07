function Update-NetworkGraphData {
    <#
    .SYNOPSIS
        Harvests the data files from their public sources into the user cache.

    .DESCRIPTION
        Downloads each kind from the URLs its sources name and writes it to
        $env:LOCALAPPDATA\NetworkGraph\data (on Linux and macOS the local application data
        folder), atomically. From then on every command reads the user copy instead of the one
        bundled with the module. Never writes into the module folder: in a clone of the repository,
        Invoke-Build UpdateData runs this command and then promotes the files to src/.

        Kinds: SpecialUse (IANA special-purpose registries), CloudRanges (Azure Service Tags, AWS
        ip-ranges.json, Google goog.json and cloud.json; gzip), Oui (IEEE MA-L), Ports (IANA
        service names and ports). CloudReservations and IpSources are written by hand and are not
        harvested. Network: HTTPS GET only.

    .PARAMETER Kind
        Kinds to harvest. Default: all four.

    .PARAMETER Path
        Folder to write to. Default: the user cache.

    .PARAMETER PassThru
        Return a NetworkGraph.DataFile row per file written.

    .EXAMPLE
        Update-NetworkGraphData -Kind CloudRanges -PassThru

    .OUTPUTS
        None, or NetworkGraph.DataFile with -PassThru.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('NetworkGraph.DataFile')]
    param(
        [ValidateSet('SpecialUse', 'CloudRanges', 'Oui', 'Ports')]
        [string[]]
        $Kind = @('SpecialUse', 'CloudRanges', 'Oui', 'Ports'),

        [string]
        $Path = $script:NetworkGraphDataUserRoot,

        [switch]
        $PassThru
    )

    $pulled = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    foreach ($item in $Kind) {
        $target = Join-Path $Path $script:NetworkGraphDataKinds[$item]
        if (-not $PSCmdlet.ShouldProcess($target, "Harvest $item")) { continue }
        Write-Verbose "Harvesting $item"
        $document = switch ($item) {
            'SpecialUse' { Get-NetworkGraphSpecialUseHarvest -Pulled $pulled }
            'CloudRanges' { Get-NetworkGraphCloudRangeHarvest -Pulled $pulled }
            'Oui' { Get-NetworkGraphOuiHarvest -Pulled $pulled }
            'Ports' { Get-NetworkGraphPortHarvest -Pulled $pulled }
        }
        $file = Write-NetworkGraphDataFile -Path $target -Document $document
        $script:NetworkGraphDataMemo.Remove($item)
        Write-Verbose "$item -> $($file.FullName) ($($file.Length) bytes)"
        if ($PassThru) { Get-NetworkGraphDataFileInfo -Kind $item -Path $file.FullName }
    }
}
