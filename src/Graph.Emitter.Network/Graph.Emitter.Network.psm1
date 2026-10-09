# Graph.Emitter.Network module root: module-scope state and wiring only. Every function lives in its own
# file under Private\ (helpers) or Public\ (one exported function per file, Verb-Noun.ps1).

# Data files. The user cache wins over the copy bundled with the module; only an Invoke-Build
# task writes the bundled copy. Tests repoint both roots with InModuleScope.
$script:NetworkGraphDataBundledRoot = Join-Path $PSScriptRoot 'data'
$script:NetworkGraphDataUserRoot = Join-Path ($env:LOCALAPPDATA ?? [Environment]::GetFolderPath('LocalApplicationData')) 'NetworkGraph' 'data'
$script:NetworkGraphDataKinds = [ordered]@{
    CloudReservations = 'cloud-reservations.json'
    SpecialUse        = 'special-use.json'
    CloudRanges       = 'cloud-ranges.json.gz'
    Oui               = 'oui.json'
    Ports             = 'ports.json'
    IpSources         = 'ip-sources.json'
}
# Kinds Update-NetworkGraphData can harvest. CloudReservations and IpSources are written by hand
# from the pages their sources name.
$script:NetworkGraphHarvestKinds = 'SpecialUse', 'CloudRanges', 'Oui', 'Ports'
# Parsed documents and lookup indexes, keyed by path|ticks|size so a refreshed file is reread.
$script:NetworkGraphDataMemo = @{}

# The platform the observe commands branch on, and the ufw.conf Get-NetworkHost reads. Tests
# set both with InModuleScope to exercise another platform's path.
$script:NetworkGraphPlatform = $IsWindows ? 'Windows' : ($IsLinux ? 'Linux' : ($IsMacOS ? 'macOS' : 'Unknown'))
$script:NetworkGraphUfwConfPath = '/etc/ufw/ufw.conf'

# Seams the tests replace: every native command and every HTTP request goes through these.
$script:NetworkGraphNativeInvoker = $null
$script:NetworkGraphWebInvoker = $null
# The TCP connect Test-NetworkGraphTcpPortBatch makes; tests replace it to time connects without a network.
$script:NetworkGraphTcpConnector = $null

# Graph contract: property names per node kind, in order. docs/graph-shape.md documents the same
# table and Pester asserts the two agree. Edges are From, To, Kind, Source.
$script:NetworkGraphNodeBase = 'Id', 'Kind', 'Name', 'Source'
$script:NetworkGraphNodeContract = [ordered]@{
    Host       = @('HostName', 'Os')
    Interface  = @('InterfaceName', 'InterfaceKey', 'Ip', 'PrefixLength', 'MacAddress', 'Vendor', 'Status')
    Subnet     = @('Cidr', 'Cloud', 'PrefixLength', 'Usable', 'BelowCloudMinimum')
    Route      = @('Destination', 'PrefixLength', 'NextHop', 'InterfaceName', 'InterfaceKey', 'Metric')
    Hop        = @('Target', 'Hop', 'Ip', 'RttMs', 'AvgMs', 'LossPercent', 'Responded')
    Connection = @('Protocol', 'LocalIp', 'LocalPort', 'RemoteIp', 'RemotePort', 'State', 'ProcessId')
    Process    = @('ProcessId', 'ProcessName')
    RemoteHost = @('Ip', 'RemoteHost', 'MacAddress', 'Vendor', 'Cloud', 'Service', 'Asn', 'Owner', 'OpenPorts')
    Cloud      = @('Cloud')
    Asn        = @('Asn', 'Owner')
}
$script:NetworkGraphEdgeKinds = 'Contains', 'RoutesTo', 'HopsTo', 'ConnectsTo', 'OwnedBy', 'ResolvesTo', 'BelongsTo'
$script:NetworkGraphFindingKinds = 'SubnetOverlap', 'BelowCloudMinimum', 'NonCloudPublicConnection', 'WildcardListener', 'RouteWithoutInterface'

#region functions (Invoke-Build Assemble replaces this region with the files' contents)
foreach ($folder in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' -File | Sort-Object Name) {
        . $file.FullName
    }
}
Remove-Variable -Name folder, file -ErrorAction SilentlyContinue
#endregion functions

# Default views.
Update-TypeData -TypeName 'NetworkGraph.Subnet' -DefaultDisplayPropertySet Cidr, Cloud, FirstUsable, LastUsable, Usable, Gateway -Force
Update-TypeData -TypeName 'NetworkGraph.PlannedSubnet' -DefaultDisplayPropertySet Name, Cidr, RequestedHosts, Usable, FirstUsable, LastUsable -Force
Update-TypeData -TypeName 'NetworkGraph.SubnetPlan' -DefaultDisplayPropertySet Parent, Cloud, Subnets, Remaining -Force
Update-TypeData -TypeName 'NetworkGraph.IPAddressInfo' -DefaultDisplayPropertySet Ip, Version, Scope, Cloud, Service, Source -Force
Update-TypeData -TypeName 'NetworkGraph.Connection' -DefaultDisplayPropertySet Protocol, LocalIp, LocalPort, RemoteIp, RemotePort, State, ProcessName -Force
Update-TypeData -TypeName 'NetworkGraph.Port' -DefaultDisplayPropertySet Target, Port, Protocol, Open, Service, LatencyMs -Force
Update-TypeData -TypeName 'NetworkGraph.Hop' -DefaultDisplayPropertySet Hop, Ip, Host, RttMs, AvgMs, LossPercent, Responded -Force
Update-TypeData -TypeName 'NetworkGraph.Route' -DefaultDisplayPropertySet Destination, PrefixLength, NextHop, Interface, Metric -Force
Update-TypeData -TypeName 'NetworkGraph.Neighbor' -DefaultDisplayPropertySet Ip, MacAddress, Vendor, State, Interface -Force
Update-TypeData -TypeName 'NetworkGraph.Interface' -DefaultDisplayPropertySet Name, Status, Ip, PrefixLength, MacAddress, Gateway -Force
Update-TypeData -TypeName 'NetworkGraph.DataFile' -DefaultDisplayPropertySet Kind, Location, Pulled, Bytes, Entries -Force
Update-TypeData -TypeName 'NetworkGraph.Graph' -MemberType ScriptProperty -MemberName NodeCount -Value { @($this.Nodes).Count } -Force
Update-TypeData -TypeName 'NetworkGraph.Graph' -MemberType ScriptProperty -MemberName EdgeCount -Value { @($this.Edges).Count } -Force
Update-TypeData -TypeName 'NetworkGraph.Graph' -MemberType ScriptProperty -MemberName FindingCount -Value { @($this.Findings).Count } -Force
Update-TypeData -TypeName 'NetworkGraph.Graph' -DefaultDisplayPropertySet Root, NodeCount, EdgeCount, FindingCount -Force

Write-NetworkGraphPlatformWarning

$manifest = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'Graph.Emitter.Network.psd1')
Export-ModuleMember -Function $manifest.FunctionsToExport
