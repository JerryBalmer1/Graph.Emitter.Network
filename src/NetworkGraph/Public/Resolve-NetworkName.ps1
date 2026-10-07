function Resolve-NetworkName {
    <#
    .SYNOPSIS
        Resolves DNS names and addresses: A, AAAA, PTR, MX, TXT, NS, CNAME and SRV records.

    .DESCRIPTION
        Native: Resolve-DnsName -DnsOnly on Windows; dig on Linux, or nslookup when dig is missing
        (A and AAAA only). The .NET floor, System.Net.Dns, answers A, AAAA and PTR through the
        system resolver, with no TTL and no -Server; any other type, or -Server, needs a native
        tool and is a terminating error naming it.

        An address given as -Name defaults to a PTR query, anything else to A.

    .PARAMETER Name
        Names or addresses. Accepts the pipeline and objects with a Name, Ip or RemoteIp property.

    .PARAMETER Type
        A, AAAA, PTR, MX, TXT, NS, CNAME or SRV.

    .PARAMETER Server
        DNS server to ask instead of the system resolver (native tools only).

    .PARAMETER Tool
        Auto (native when installed, else .NET), Native, or DotNet.

    .EXAMPLE
        Resolve-NetworkName example.com, 1.1.1.1

    .EXAMPLE
        Resolve-NetworkName google.com -Type MX -Server 1.1.1.1

    .OUTPUTS
        NetworkGraph.DnsRecord: Query, Name, Type, Ttl, Data, Section, Server, Source.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.DnsRecord')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Ip', 'RemoteIp')]
        [string[]]
        $Name,

        [ValidateSet('A', 'AAAA', 'PTR', 'MX', 'TXT', 'NS', 'CNAME', 'SRV')]
        [string]
        $Type,

        [string]
        $Server,

        [ValidateSet('Auto', 'Native', 'DotNet')]
        [string]
        $Tool = 'Auto'
    )

    begin {
        $candidates = $IsWindows ? @('Resolve-DnsName') : @('dig', 'nslookup')
        $chosen = Resolve-NetworkGraphTool -Tool $Tool -Candidate $candidates -CommandName 'Resolve-NetworkName'
        if ($chosen -eq 'DotNet' -and $Server) {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.NotSupportedException]::new("Resolve-NetworkName -Server needs a native resolver ($($candidates -join ' or ')); the .NET floor only asks the system resolver. Install one and use -Tool Native."),
                    'ServerNeedsNativeTool', [System.Management.Automation.ErrorCategory]::NotImplemented, $Server))
        }
    }

    process {
        foreach ($query in $Name) {
            $isAddress = $true
            try { $null = ConvertTo-NetworkGraphIpValue -Ip $query } catch { $isAddress = $false }
            $recordType = $Type ? $Type : ($isAddress ? 'PTR' : 'A')
            if (($chosen -eq 'DotNet' -and $recordType -notin 'A', 'AAAA', 'PTR') -or ($chosen -eq 'nslookup' -and $recordType -notin 'A', 'AAAA')) {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.NotSupportedException]::new("Resolve-NetworkName -Type $recordType is not available with $chosen. Install dig (dnsutils or bind-utils) on Linux, or use Resolve-DnsName on Windows, then run with -Tool Native."),
                        'RecordTypeNeedsNativeTool', [System.Management.Automation.ErrorCategory]::NotImplemented, $recordType))
            }

            $rows = switch ($chosen) {
                'Resolve-DnsName' {
                    $arguments = @{ Name = $query; Type = $recordType; DnsOnly = $true; ErrorAction = 'Stop' }
                    if ($Server) { $arguments.Server = $Server }
                    $source = "Resolve-DnsName -Name $query -Type $recordType -DnsOnly" + ($Server ? " -Server $Server" : '')
                    try {
                        foreach ($row in ConvertFrom-NetworkGraphResolveDnsName -InputObject @(Resolve-DnsName @arguments)) { $row | Add-Member Source $source -PassThru }
                    }
                    catch { Write-Error -Message "${query}: $($_.Exception.Message)" -ErrorId 'DnsQueryFailed' -Category ResourceUnavailable -TargetObject $query }
                }
                'dig' {
                    $arguments = @('+noall', '+answer')
                    if ($Server) { $arguments += "@$Server" }
                    $arguments += ($recordType -eq 'PTR' -and $isAddress) ? @('-x', $query) : @($query, $recordType)
                    $run = Invoke-NetworkGraphNative -FilePath dig -ArgumentList $arguments
                    foreach ($row in ConvertFrom-NetworkGraphDigOutput -Text $run.Output) { $row | Add-Member Source $run.CommandLine -PassThru }
                }
                'nslookup' {
                    $arguments = @("-type=$recordType", $query)
                    if ($Server) { $arguments += $Server }
                    $run = Invoke-NetworkGraphNative -FilePath nslookup -ArgumentList $arguments
                    foreach ($row in ConvertFrom-NetworkGraphNslookupOutput -Text $run.Output) { $row | Add-Member Source $run.CommandLine -PassThru }
                }
                'DotNet' {
                    try {
                        if ($recordType -eq 'PTR') {
                            $entry = [System.Net.Dns]::GetHostEntry([System.Net.IPAddress]::Parse((ConvertTo-NetworkGraphIpValue -Ip $query).Ip))
                            if ($entry.HostName -and $entry.HostName -ne $query) {
                                [pscustomobject]@{ Name = $query; Type = 'PTR'; Ttl = $null; Data = $entry.HostName.TrimEnd('.'); Section = 'Answer'; Source = "[System.Net.Dns]::GetHostEntry('$query')" }
                            }
                        }
                        else {
                            $family = ($recordType -eq 'AAAA') ? 'InterNetworkV6' : 'InterNetwork'
                            foreach ($address in [System.Net.Dns]::GetHostAddresses($query) | Where-Object AddressFamily -eq $family) {
                                [pscustomobject]@{ Name = $query; Type = $recordType; Ttl = $null; Data = $address.ToString(); Section = 'Answer'; Source = "[System.Net.Dns]::GetHostAddresses('$query')" }
                            }
                        }
                    }
                    catch { Write-Error -Message "${query}: $($_.Exception.InnerException.Message ?? $_.Exception.Message)" -ErrorId 'DnsQueryFailed' -Category ResourceUnavailable -TargetObject $query }
                }
            }

            foreach ($row in $rows) {
                [pscustomobject]@{
                    PSTypeName = 'NetworkGraph.DnsRecord'
                    Query      = $query
                    Name       = $row.Name
                    Type       = $row.Type
                    Ttl        = $row.Ttl
                    Data       = $row.Data
                    Section    = $row.Section
                    Server     = $row.PSObject.Properties['Server'] ? $row.Server : ($Server ? $Server : $null)
                    Source     = $row.Source
                }
            }
        }
    }
}
