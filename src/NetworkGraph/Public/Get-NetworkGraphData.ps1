function Get-NetworkGraphData {
    <#
    .SYNOPSIS
        Lists the data files the module reads, with their sources and pulled dates, or returns one.

    .DESCRIPTION
        Without -Kind, one NetworkGraph.DataFile row per kind: Location (User when the user cache
        holds the file, else Bundled), Path, Bytes, Pulled, AgeDays, MaxAgeDays, Entries and
        Sources. With -Kind, the same rows for those kinds plus Data, the parsed document. -Sources
        returns one NetworkGraph.DataSource row (Kind, Url, Title, Pulled) per source instead.
        Reads local files only.

    .PARAMETER Kind
        CloudReservations, SpecialUse, CloudRanges, Oui, Ports, IpSources.

    .PARAMETER Sources
        Return the source rows.

    .EXAMPLE
        Get-NetworkGraphData

    .EXAMPLE
        Get-NetworkGraphData -Sources | Format-Table Kind, Pulled, Url

    .EXAMPLE
        (Get-NetworkGraphData -Kind CloudReservations).Data.clouds.Azure.reserved

    .OUTPUTS
        NetworkGraph.DataFile, or NetworkGraph.DataSource with -Sources.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.DataFile', 'NetworkGraph.DataSource')]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('CloudReservations', 'SpecialUse', 'CloudRanges', 'Oui', 'Ports', 'IpSources')]
        [string[]]
        $Kind,

        [switch]
        $Sources
    )

    $kinds = $Kind ? $Kind : @($script:NetworkGraphDataKinds.Keys)
    foreach ($item in $kinds) {
        $info = Get-NetworkGraphDataFileInfo -Kind $item
        if ($Sources) { $info.Sources; continue }
        if ($Kind -and $info.Path) {
            $info | Add-Member -NotePropertyName Data -NotePropertyValue (Get-NetworkGraphDataDocument -Kind $item)
        }
        $info
    }
}
