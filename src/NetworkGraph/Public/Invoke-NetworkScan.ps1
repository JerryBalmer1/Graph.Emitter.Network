function Invoke-NetworkScan {
    <#
    .SYNOPSIS
        Scans ports on one or more hosts: nmap when it is installed, otherwise TCP connect tests.

    .DESCRIPTION
        If nmap is on PATH it runs as nmap -oX - -n -Pn -p <ports> [-sU] <targets>, and its XML is
        parsed into the rows Test-NetworkPort returns. Nothing else is added: no scripts, no
        version or OS detection. If nmap is absent (or with -Tool DotNet) each target and port is
        tested with a TCP connect through System.Net.Sockets.TcpClient, -ThrottleLimit at a time
        (UDP: one datagram per port, as Test-NetworkPort does). NetworkGraph ships no scanner and
        no nmap.

        Only scan hosts you are allowed to scan.

        A target may be a CIDR prefix; without nmap it expands to its usable addresses (at most
        4096).

    .PARAMETER Target
        Host names, addresses or CIDR prefixes.

    .PARAMETER Port
        Ports to scan. Default 22, 80, 443, 445, 3389, 8080.

    .PARAMETER Protocol
        Tcp (default) or Udp. nmap -sU needs root or Administrator.

    .PARAMETER Timeout
        Milliseconds per connect attempt without nmap. Default 1000.

    .PARAMETER ThrottleLimit
        Concurrent connects without nmap. Default 64.

    .PARAMETER Tool
        Auto (nmap when installed, else .NET), Native (nmap, error if absent), or DotNet.

    .EXAMPLE
        Invoke-NetworkScan 192.168.0.0/28 -Port 22, 80, 443 | Where-Object Open

    .OUTPUTS
        NetworkGraph.Port: Target, Ip, Port, Protocol, Open, Service, LatencyMs, Source.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.Port')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Ip', 'RemoteIp', 'Cidr')]
        [string[]]
        $Target,

        [ValidateRange(1, 65535)]
        [int[]]
        $Port = @(22, 80, 443, 445, 3389, 8080),

        [ValidateSet('Tcp', 'Udp')]
        [string]
        $Protocol = 'Tcp',

        [ValidateRange(1, 60000)]
        [int]
        $Timeout = 1000,

        [ValidateRange(1, 1024)]
        [int]
        $ThrottleLimit = 64,

        [ValidateSet('Auto', 'Native', 'DotNet')]
        [string]
        $Tool = 'Auto'
    )

    begin {
        $targets = [System.Collections.Generic.List[string]]::new()
        $chosen = Resolve-NetworkGraphTool -Tool $Tool -Candidate @('nmap') -CommandName 'Invoke-NetworkScan'
    }
    process { foreach ($item in $Target) { $targets.Add($item) } }
    end {
        if ($chosen -eq 'nmap') {
            $arguments = @('-oX', '-', '-n', '-Pn', '-p', ($Port -join ','))
            if ($Protocol -eq 'Udp') { $arguments += '-sU' }
            $arguments += $targets
            try { $run = Invoke-NetworkGraphNative -FilePath nmap -ArgumentList $arguments -TimeoutSec 3600 -OkExitCodes 0 }
            catch {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new("$($_.Exception.Message) Run Invoke-NetworkScan -Tool DotNet to scan without nmap.", $_.Exception),
                        'NmapFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, ($arguments -join ' ')))
            }
            foreach ($row in ConvertFrom-NetworkGraphNmapXml -Text $run.Output) {
                [pscustomobject]@{
                    PSTypeName = 'NetworkGraph.Port'
                    Target     = $row.Host ? $row.Host : $row.Ip
                    Ip         = $row.Ip
                    Port       = $row.Port
                    Protocol   = $row.Protocol
                    Open       = $row.Open
                    Service    = $row.Service ? $row.Service : (Find-NetworkGraphPortService -Port $row.Port -Protocol $row.Protocol)
                    LatencyMs  = $null
                    Source     = $run.CommandLine
                }
            }
            return
        }

        # No nmap: expand prefixes, resolve names, then connect.
        $hosts = foreach ($item in $targets) {
            if ($item.Contains('/')) {
                $prefix = Resolve-NetworkGraphPrefix -Cidr $item
                $subnet = New-NetworkGraphSubnet -Prefix $prefix -Cloud None
                if ($subnet.Usable -gt 4096) {
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                            [System.ArgumentException]::new("$item has $($subnet.Usable) addresses; without nmap Invoke-NetworkScan expands at most 4096. Install nmap or split the prefix (New-SubnetPlan $item -PrefixLength 20)."),
                            'TooManyTargets', [System.Management.Automation.ErrorCategory]::LimitsExceeded, $item))
                }
                $value = (ConvertTo-NetworkGraphIpValue -Ip $subnet.FirstUsable).Value
                $last = (ConvertTo-NetworkGraphIpValue -Ip $subnet.LastUsable).Value
                while ($value -le $last) {
                    $ip = ConvertFrom-NetworkGraphIpValue -Value $value -Version $prefix.Version
                    [pscustomobject]@{ Target = $ip; Ip = $ip }
                    $value = $value + 1
                }
            }
            else {
                $ip = Resolve-NetworkGraphTarget -Target $item
                if ($ip) { [pscustomobject]@{ Target = $item; Ip = $ip } }
            }
        }

        if ($Protocol -eq 'Udp') {
            foreach ($entry in $hosts) { Test-NetworkPort -Target $entry.Ip -Port $Port -Protocol Udp -Timeout $Timeout | ForEach-Object { $_.Target = $entry.Target; $_ } }
            return
        }
        # TCP goes to the batch helper rather than Test-NetworkPort so that -ThrottleLimit spans
        # every target and port at once; Test-NetworkPort batches one target at a time.
        $pairs = foreach ($entry in $hosts) { foreach ($number in $Port) { [pscustomobject]@{ Target = $entry.Target; Ip = $entry.Ip; Port = $number } } }
        foreach ($row in Test-NetworkGraphTcpPortBatch -Pair @($pairs) -Timeout $Timeout -ThrottleLimit $ThrottleLimit) {
            [pscustomobject]@{
                PSTypeName = 'NetworkGraph.Port'
                Target     = $row.Target
                Ip         = $row.Ip
                Port       = $row.Port
                Protocol   = 'Tcp'
                Open       = $row.Open
                Service    = Find-NetworkGraphPortService -Port $row.Port -Protocol Tcp
                LatencyMs  = $row.LatencyMs
                Source     = "[System.Net.Sockets.TcpClient]::new([System.Net.Sockets.AddressFamily]::$([System.Net.IPAddress]::Parse($row.Ip).AddressFamily)).ConnectAsync('$($row.Ip)', $($row.Port)).Wait($Timeout)  # $ThrottleLimit at a time; nmap not used"
            }
        }
    }
}
