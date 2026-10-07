function ConvertFrom-NetworkGraphIpNeighJson {
    # Not exported. 'ip -j neigh' JSON to neighbour rows. Structured; state is the first of the
    # state flags. Pinned by tests/fixtures/ip-neigh.linux.json.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    if (-not $Text.Trim()) { return }
    foreach ($item in @($Text | ConvertFrom-Json -AsHashtable)) {
        New-NetworkGraphNeighborRow -Ip $item['dst'] -MacAddress $item['lladdr'] -State (@($item['state'])[0]) -Interface $item['dev']
    }
}
