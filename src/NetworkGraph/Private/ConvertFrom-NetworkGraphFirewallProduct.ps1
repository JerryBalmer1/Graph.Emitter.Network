function ConvertFrom-NetworkGraphFirewallProduct {
    # Not exported. SecurityCenter2 FirewallProduct rows (live, or
    # tests/fixtures/FirewallProduct.windows.json) to { Name, Enabled, ProductState }. Structured.
    # productState packs three bytes, 0xTTSSDD: SS is the state, 0x10 (or 0x11) on and 0x00 (or
    # 0x01) off; 331776 = 0x051000 is on, 393472 = 0x060100 is off.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $InputObject
    )

    foreach ($item in $InputObject) {
        $state = [int]$item.productState
        [pscustomobject]@{
            Name         = [string]$item.displayName
            Enabled      = (($state -shr 8) -band 0xF0) -eq 0x10
            ProductState = $state
        }
    }
}
