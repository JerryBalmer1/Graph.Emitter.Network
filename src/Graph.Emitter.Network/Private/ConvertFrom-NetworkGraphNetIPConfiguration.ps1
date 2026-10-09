function ConvertFrom-NetworkGraphNetIPConfiguration {
    # Not exported. Get-NetworkGraphNetIPConfiguration rows (live, or the JSON fixture
    # tests/fixtures/Get-NetIPConfiguration.windows.json) to interface rows. Structured.
    # InterfaceKey is the adapter's InterfaceGuid.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $InputObject
    )

    foreach ($item in $InputObject) {
        New-NetworkGraphInterfaceRow -Name $item.InterfaceAlias -InterfaceKey $item.InterfaceGuid -Description $item.InterfaceDescription -Status $item.Status `
            -MacAddress $item.MacAddress -Address @($item.Ip) -Gateway @($item.Gateway) -Dns @($item.Dns)
    }
}
