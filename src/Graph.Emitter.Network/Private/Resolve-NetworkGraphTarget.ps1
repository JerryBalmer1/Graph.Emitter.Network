function Resolve-NetworkGraphTarget {
    # Not exported. A host name or address to the address to connect to: an address is returned as
    # is, a name through System.Net.Dns (IPv4 preferred). A name that does not resolve is a
    # non-terminating error and $null.
    param([Parameter(Mandatory)][string]$Target)

    try { return (ConvertTo-NetworkGraphIpValue -Ip $Target).Ip } catch { Write-Verbose "$Target is a name" }
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($Target)
        $pick = @($addresses | Where-Object AddressFamily -eq 'InterNetwork') + @($addresses) | Select-Object -First 1
        $pick.ToString()
    }
    catch {
        Write-Error -Message "${Target}: does not resolve ($($_.Exception.InnerException.Message ?? $_.Exception.Message))." -ErrorId 'TargetNotResolved' -Category ObjectNotFound -TargetObject $Target
        $null
    }
}
