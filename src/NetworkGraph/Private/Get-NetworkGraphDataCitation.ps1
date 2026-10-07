function Get-NetworkGraphDataCitation {
    # Not exported. How a verdict drawn from a data file cites it: '<file> pulled <date> (<url>)',
    # the file in use (user cache or bundled), its pulled date (the newest source's when the file
    # has none), and the first source whose url matches -Match (the cloud's own list, the IPv4 or
    # IPv6 registry), else the first source; -Cloud picks that cloud's own source in CloudRanges
    # and CloudReservations. The Source of every data-derived row and node.
    param(
        [Parameter(Mandatory)]
        [string]
        $Kind,

        [string]
        $Match,

        [string]
        $Cloud
    )

    if ($Cloud -and -not $Match) {
        $Match = switch ("$Kind/$Cloud") {
            'CloudRanges/Azure' { 'ServiceTags_Public' }
            'CloudRanges/AWS' { 'ip-ranges\.amazonaws\.com' }
            'CloudRanges/GCP' { '/cloud\.json$' }
            'CloudRanges/Google' { '/goog\.json$' }
            'CloudReservations/Azure' { 'learn\.microsoft\.com' }
            'CloudReservations/AWS' { 'docs\.aws\.amazon\.com' }
            'CloudReservations/GCP' { 'cloud\.google\.com' }
        }
    }

    $document = Get-NetworkGraphDataDocument -Kind $Kind
    $sources = @($document['sources'])
    $source = ($Match ? @($sources | Where-Object { $_['url'] -match $Match })[0] : $null) ?? $sources[0]
    $pulled = $document['pulled'] ?? (@($sources | ForEach-Object { $_['pulled'] } | Sort-Object) | Select-Object -Last 1)
    '{0} pulled {1} ({2})' -f (Split-Path -Leaf $document['_path']), $pulled, $source['url']
}
