function Get-NetworkGraphFirewallProduct {
    # Not exported. The firewall products registered with Windows Security Center
    # (root/SecurityCenter2 FirewallProduct, CIM): Norton, McAfee, ESET and the like. Client SKUs
    # only; on Windows Server, or when the namespace is unavailable, returns nothing. Tests mock
    # this function; tests/fixtures/FirewallProduct.windows.json is a real row.
    try { @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName FirewallProduct -ErrorAction Stop) }
    catch { Write-Verbose "SecurityCenter2 FirewallProduct: $($_.Exception.Message)"; @() }
}
