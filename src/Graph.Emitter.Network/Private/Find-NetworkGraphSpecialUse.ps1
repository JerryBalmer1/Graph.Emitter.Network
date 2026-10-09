function Find-NetworkGraphSpecialUse {
    # Not exported. Every special-use.json row whose prefix holds the address (a
    # ConvertTo-NetworkGraphIpValue result), most specific first. The rows are resolved once per
    # file version and kept with the memoized document.
    param(
        [Parameter(Mandatory)]
        $Address
    )

    $null = Get-NetworkGraphDataDocument -Kind SpecialUse
    $memo = $script:NetworkGraphDataMemo['SpecialUse']
    if (-not $memo.Index) {
        $memo.Index = @(foreach ($entry in @($memo.Document['entries'])) {
                [pscustomobject]@{ Entry = $entry; Prefix = (Resolve-NetworkGraphPrefix -Cidr $entry['cidr']) }
            })
    }

    $memo.Index |
        Where-Object { $_.Prefix.Version -eq $Address.Version -and $Address.Value -ge $_.Prefix.Network -and $Address.Value -le $_.Prefix.Last } |
        Sort-Object { $_.Prefix.PrefixLength } -Descending |
        ForEach-Object { $_.Entry }
}
