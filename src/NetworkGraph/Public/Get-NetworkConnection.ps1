function Get-NetworkConnection {
    <#
    .SYNOPSIS
        Lists TCP and UDP connections and listeners with the owning process: the netstat
        replacement.

    .DESCRIPTION
        Native: Get-NetTCPConnection and Get-NetUDPEndpoint on Windows (OwningProcess, names from
        Get-Process); ss -tunap on Linux (processes you may not see without root show none). The
        .NET floor (IPGlobalProperties active connections and listeners) knows no process:
        ProcessId and ProcessName are $null and Source says so. Every row's Source names the tool
        and exact command line that produced it.

        A listener or a UDP socket with no peer has RemoteIp and RemotePort $null. IPv4-mapped
        IPv6 addresses are shown as IPv4.

        -Resolve adds RemoteHost (reverse DNS, all lookups in parallel, -ResolveTimeoutMs in
        total), and Cloud, Service, Asn and Owner from the bundled cloud ranges (Test-IPAddress).
        Asn and Owner are known only for cloud addresses; the module does no BGP lookup.

    .PARAMETER Protocol
        Tcp, Udp, or both (default).

    .PARAMETER State
        Keep only rows in these states (Listen, Established, TimeWait, CloseWait, ...).

    .PARAMETER Resolve
        Add RemoteHost, Cloud, Service, Asn and Owner.

    .PARAMETER ResolveTimeoutMs
        Total time for the reverse lookups. Default 3000.

    .PARAMETER Tool
        Auto (native when installed, else .NET), Native, or DotNet.

    .EXAMPLE
        Get-NetworkConnection -State Established -Resolve | Format-Table RemoteIp, RemoteHost, Cloud, Service, ProcessName

    .EXAMPLE
        Get-NetworkConnection -State Listen | Where-Object LocalIp -in '0.0.0.0', '::'

    .OUTPUTS
        NetworkGraph.Connection: Protocol, LocalIp, LocalPort, RemoteIp, RemotePort, State,
        ProcessId, ProcessName, Source; with -Resolve also RemoteHost, Cloud, Service, Asn, Owner.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.Connection')]
    param(
        [ValidateSet('Tcp', 'Udp')]
        [string[]]
        $Protocol = @('Tcp', 'Udp'),

        [ValidateSet('Listen', 'Established', 'TimeWait', 'CloseWait', 'SynSent', 'SynReceived', 'FinWait1', 'FinWait2', 'Closing', 'LastAck', 'Closed', 'Bound')]
        [string[]]
        $State,

        [switch]
        $Resolve,

        [int]
        $ResolveTimeoutMs = 3000,

        [ValidateSet('Auto', 'Native', 'DotNet')]
        [string]
        $Tool = 'Auto'
    )

    $candidates = $IsWindows ? @('Get-NetTCPConnection') : @('ss')
    $chosen = Resolve-NetworkGraphTool -Tool $Tool -Candidate $candidates -CommandName 'Get-NetworkConnection'

    $rows = switch ($chosen) {
        'Get-NetTCPConnection' {
            $names = @{}
            foreach ($process in Get-Process) { $names[$process.Id] = $process.ProcessName }
            if ('Tcp' -in $Protocol) {
                $tcp = @(Get-NetTCPConnection -ErrorAction SilentlyContinue)
                foreach ($row in ConvertFrom-NetworkGraphNetTcpConnection -InputObject $tcp -ProcessName $names) { $row | Add-Member Source 'Get-NetTCPConnection' -PassThru }
            }
            if ('Udp' -in $Protocol) {
                $udp = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue)
                foreach ($row in ConvertFrom-NetworkGraphNetUdpEndpoint -InputObject $udp -ProcessName $names) { $row | Add-Member Source 'Get-NetUDPEndpoint' -PassThru }
            }
        }
        'ss' {
            # Always both protocols: with only -t or -u, ss drops the Netid column the parser reads.
            $run = Invoke-NetworkGraphNative -FilePath ss -ArgumentList '-tunap'
            foreach ($row in ConvertFrom-NetworkGraphSsOutput -Text $run.Output) { $row | Add-Member Source $run.CommandLine -PassThru }
        }
        'DotNet' {
            $properties = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
            $note = ' (.NET floor: no process information)'
            if ('Tcp' -in $Protocol) {
                foreach ($item in $properties.GetActiveTcpListeners()) {
                    New-NetworkGraphConnectionRow -Protocol Tcp -LocalIp (ConvertTo-NetworkGraphIpValue -Ip $item.Address.ToString() -Unmap).Ip -LocalPort $item.Port -State Listen |
                        Add-Member Source "[IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()$note" -PassThru
                }
                foreach ($item in $properties.GetActiveTcpConnections()) {
                    New-NetworkGraphConnectionRow -Protocol Tcp -LocalIp (ConvertTo-NetworkGraphIpValue -Ip $item.LocalEndPoint.Address.ToString() -Unmap).Ip -LocalPort $item.LocalEndPoint.Port `
                        -RemoteIp (ConvertTo-NetworkGraphIpValue -Ip $item.RemoteEndPoint.Address.ToString() -Unmap).Ip -RemotePort $item.RemoteEndPoint.Port -State ([string]$item.State) |
                        Add-Member Source "[IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpConnections()$note" -PassThru
                }
            }
            if ('Udp' -in $Protocol) {
                foreach ($item in $properties.GetActiveUdpListeners()) {
                    New-NetworkGraphConnectionRow -Protocol Udp -LocalIp (ConvertTo-NetworkGraphIpValue -Ip $item.Address.ToString() -Unmap).Ip -LocalPort $item.Port |
                        Add-Member Source "[IPGlobalProperties]::GetIPGlobalProperties().GetActiveUdpListeners()$note" -PassThru
                }
            }
        }
    }

    $rows = @($rows | Where-Object { $_.Protocol -in $Protocol })
    if ($State) { $rows = @($rows | Where-Object { $_.State -in $State }) }

    if ($Resolve) {
        $remote = @($rows.RemoteIp | Where-Object { $_ } | Select-Object -Unique)
        $names = Resolve-NetworkGraphReverseName -Ip $remote -TimeoutMs $ResolveTimeoutMs
        $info = @{}
        foreach ($ip in $remote) { $info[$ip] = Test-IPAddress -Address $ip }
    }
    foreach ($row in $rows) {
        $row.PSObject.TypeNames.Insert(0, 'NetworkGraph.Connection')
        if ($Resolve) {
            $detail = $row.RemoteIp ? $info[$row.RemoteIp] : $null
            $row | Add-Member -NotePropertyMembers ([ordered]@{
                    RemoteHost = $row.RemoteIp ? $names[$row.RemoteIp] : $null
                    Cloud      = $detail ? $detail.Cloud : $null
                    Service    = $detail ? $detail.Service : $null
                    Asn        = $detail ? $detail.Asn : $null
                    Owner      = $detail ? $detail.Owner : $null
                })
        }
        $row
    }
}
