function Test-NetworkPort {
    <#
    .SYNOPSIS
        Tests whether a TCP (or UDP) port answers: the telnet replacement.

    .DESCRIPTION
        Auto uses the .NET path, System.Net.Sockets.TcpClient, which honours -Timeout and measures
        LatencyMs. The native tools are still there by name with -Tool Native: Test-NetConnection
        -Port on Windows (TCP only; it ignores -Timeout and can take about 20 seconds on a filtered
        port), nc -z -v on Linux. They leave LatencyMs $null.

        UDP has no handshake. The .NET floor sends one empty datagram and listens: a reply is Open
        $true, an ICMP port-unreachable is $false, silence is $null (open or filtered, unknown).
        nc -u reports every UDP port as open, so UDP with nc is answered the same way, through the
        .NET floor, and Source says so. Service is the IANA name from data/ports.json.

    .PARAMETER Target
        Host names or addresses. Accepts the pipeline and objects with a Target, Ip or RemoteIp
        property.

    .PARAMETER Port
        One or more ports.

    .PARAMETER Protocol
        Tcp (default) or Udp.

    .PARAMETER Timeout
        Milliseconds per attempt. Default 2000.

    .PARAMETER Tool
        Auto (the .NET TcpClient path; see the description), Native (Test-NetConnection on
        Windows, nc on Linux), or DotNet.

    .EXAMPLE
        Test-NetworkPort github.com -Port 22, 443 -Tool DotNet

    .OUTPUTS
        NetworkGraph.Port: Target, Ip, Port, Protocol, Open, Service, LatencyMs, Source.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.Port')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Ip', 'RemoteIp', 'ComputerName')]
        [string[]]
        $Target,

        [Parameter(Mandatory, Position = 1)]
        [ValidateRange(1, 65535)]
        [int[]]
        $Port,

        [ValidateSet('Tcp', 'Udp')]
        [string]
        $Protocol = 'Tcp',

        [ValidateRange(1, 60000)]
        [int]
        $Timeout = 2000,

        [ValidateSet('Auto', 'Native', 'DotNet')]
        [string]
        $Tool = 'Auto'
    )

    begin {
        # Auto is the .NET TcpClient path, not the native tool: Test-NetConnection ignores -Timeout
        # and spends about 20 s on a filtered port, so a port check that should take -Timeout ms
        # would take twenty seconds per port. -Tool Native still runs Test-NetConnection or nc.
        $candidates = $IsWindows ? @('Test-NetConnection') : @('nc')
        $chosen = ($Tool -eq 'Auto') ? 'DotNet' : (Resolve-NetworkGraphTool -Tool $Tool -Candidate $candidates -CommandName 'Test-NetworkPort')
        $newRow = {
            param($Target, $Ip, $Port, $Open, $LatencyMs, $Source)
            [pscustomobject]@{
                PSTypeName = 'NetworkGraph.Port'
                Target     = $Target
                Ip         = $Ip
                Port       = [int]$Port
                Protocol   = $Protocol
                Open       = $Open
                Service    = Find-NetworkGraphPortService -Port $Port -Protocol $Protocol
                LatencyMs  = $LatencyMs
                Source     = $Source
            }
        }
    }

    process {
        foreach ($item in $Target) {
            $ip = Resolve-NetworkGraphTarget -Target $item
            if (-not $ip) { continue }

            if ($Protocol -eq 'Udp') {
                $note = ($chosen -ne 'DotNet') ? " ($chosen cannot tell open from filtered UDP; .NET used)" : ''
                foreach ($number in $Port) {
                    $client = [System.Net.Sockets.UdpClient]::new([System.Net.IPAddress]::Parse($ip).AddressFamily)
                    $open = $null
                    try {
                        $client.Client.ReceiveTimeout = $Timeout
                        $client.Connect([System.Net.IPAddress]::Parse($ip), $number)
                        $null = $client.Send([byte[]]::new(0), 0)
                        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
                        $null = $client.Receive([ref]$remote)
                        $open = $true
                    }
                    catch [System.Net.Sockets.SocketException] {
                        if ($_.Exception.SocketErrorCode -in 'ConnectionReset', 'ConnectionRefused') { $open = $false }
                    }
                    catch {
                        $inner = $_.Exception.InnerException
                        if ($inner -is [System.Net.Sockets.SocketException] -and $inner.SocketErrorCode -in 'ConnectionReset', 'ConnectionRefused') { $open = $false }
                    }
                    finally { $client.Dispose() }
                    & $newRow $item $ip $number $open $null "[System.Net.Sockets.UdpClient]::new().Send(empty) to ${ip}:$number, Receive timeout $Timeout$note"
                }
                continue
            }

            switch ($chosen) {
                'Test-NetConnection' {
                    foreach ($number in $Port) {
                        $result = Test-NetConnection -ComputerName $ip -Port $number -WarningAction SilentlyContinue -InformationLevel Detailed
                        $row = ConvertFrom-NetworkGraphTestNetConnection -InputObject @($result)
                        & $newRow $item $ip $number $row.Open $null "Test-NetConnection -ComputerName $ip -Port $number"
                    }
                }
                'nc' {
                    foreach ($number in $Port) {
                        $run = Invoke-NetworkGraphNative -FilePath nc -ArgumentList '-z', '-v', '-n', '-w', "$([math]::Ceiling($Timeout / 1000))", $ip, "$number" -TimeoutSec ([math]::Ceiling($Timeout / 1000) + 10)
                        $parsed = ConvertFrom-NetworkGraphNcOutput -Text "$($run.Output)`n$($run.Error)" | Select-Object -First 1
                        $open = $parsed ? $parsed.Open : ($run.ExitCode -eq 0)
                        & $newRow $item $ip $number $open $null $run.CommandLine
                    }
                }
                'DotNet' {
                    $pairs = foreach ($number in $Port) { [pscustomobject]@{ Target = $item; Ip = $ip; Port = $number } }
                    foreach ($row in Test-NetworkGraphTcpPortBatch -Pair @($pairs) -Timeout $Timeout) {
                        & $newRow $item $ip $row.Port $row.Open $row.LatencyMs "[System.Net.Sockets.TcpClient]::new().ConnectAsync('$ip', $($row.Port)), timeout $Timeout"
                    }
                }
            }
        }
    }
}
