# NetworkGraph manual check list

Module version: 0.1.1
Last updated: 2026-10-07

Every block starts a fresh process (`pwsh -NoProfile -Command { ... }`) and imports the module from `src`, so no item depends on another or on the shell it is pasted into. Objects come back across the process boundary deserialized, so lists show every property rather than the default view; the Expect lines describe what that looks like. Items are append-only: never renumber, mark a removed item "(removed in x.y.z)".

Verified for 0.1.1: items 0.1, 1.4, 1.5, 1.6 and 1.8 were rerun, and 1.10 to 1.14 added and run, on Windows 11 (PowerShell 7.6.6); their Expect lines are written from that output. Verified for 0.1.0: every item below was run on Windows 11 (PowerShell 7.6.6) and its Expect line written from that output. Items 1.1, 1.2, 1.3 and 1.7 were also run on Linux (Ubuntu 22.04 container, PowerShell 7, with the repository path changed to the container's) with the same output; 1.4, 1.5 and 1.6 depend on the host's own connections and path and were exercised on Linux through the Live Pester tests, not by these blocks.

## 0 Setup

### 0.1 Fresh import: version and exports

Imports the module from source and lists its version and exported commands.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    (Get-Module NetworkGraph).Version.ToString()
    (Get-Command -Module NetworkGraph).Count
    (Get-Command -Module NetworkGraph).Name -join ', '
}
```

Expect: `0.1.1`, then `23`, then ConvertFrom-SubnetMask, ConvertTo-NetworkGraph, ConvertTo-SubnetMask, Get-ExternalIpAddress, Get-MacAddressVendor, Get-NetworkConnection, Get-NetworkGraphData, Get-NetworkHost, Get-NetworkInterface, Get-NetworkNeighbor, Get-NetworkRoute, Get-Subnet, Get-SubnetChildren, Get-SubnetParent, Invoke-NetworkScan, New-SubnetPlan, Resolve-NetworkName, Test-IPAddress, Test-NetworkPath, Test-NetworkPort, Test-SubnetOverlap, Trace-NetworkPath, Update-NetworkGraphData.

Pester: "is version 0.1.1 and needs PowerShell 7.4", "psd1 exports match Public/", "exports 23 functions in three groups by noun", "every Public file exports exactly its function name"

## 1 First checks

### 1.1 Get-Subnet: Azure /24

An Azure /24 with its five reserved addresses.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    $subnet = Get-Subnet 10.0.0.0/24 -Cloud Azure
    $subnet
    $subnet.Reserved | Format-Table Ip, Role
}
```

Expect: a list with Cidr `10.0.0.0/24`, Network `10.0.0.0`, Broadcast `10.0.0.255`, FirstUsable `10.0.0.4`, LastUsable `10.0.0.254`, Usable `251`, Mask `255.255.255.0`, Cloud `Azure`, Gateway `10.0.0.1`, BelowCloudMinimum `False`; then five rows: 10.0.0.0 Network address, 10.0.0.1 Default gateway, 10.0.0.2 Azure DNS mapping, 10.0.0.3 Azure DNS mapping, 10.0.0.255 Broadcast address.

Pester: "Azure /24 has 251 usable and 5 reserved rows", "Azure /24 reserves .0, .1, .2, .3 and .255 with their roles"

### 1.2 New-SubnetPlan: VLSM

Four subnets fitted largest first into a /22, then the same hosts failing a /23 under Azure.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    $plan = New-SubnetPlan 10.0.0.0/22 -Hosts 250, 120, 60, 25
    $plan.Subnets | Format-Table Name, Cidr, RequestedHosts, Usable
    $plan.Remaining
    try { New-SubnetPlan 10.0.0.0/23 -Hosts 250, 120, 60, 25 -Cloud Azure } catch { $_.Exception.Message }
}
```

Expect: subnet-1 10.0.0.0/24 (250, 254 usable), subnet-2 10.0.1.0/25 (120, 126), subnet-3 10.0.1.128/26 (60, 62), subnet-4 10.0.1.192/27 (25, 30); Remaining `10.0.1.224/27` and `10.0.2.0/23`; then `Plan does not fit: 544 addresses needed (subnet-1 /24, subnet-2 /25, subnet-3 /25, subnet-4 /27), 10.0.0.0/23 has 512 under Azure; short by 32 addresses. Use a larger parent prefix or fewer hosts.`

Pester: "fits the VLSM example (250, 120, 60, 25 hosts) in a /22 with None", "fails the same example in a /23 with Azure and names the shortfall"

### 1.3 Test-SubnetOverlap: a deliberate overlap

Four prefixes, one of which (10.0.0.128/25) sits inside another.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    Test-SubnetOverlap 10.0.0.0/24, 10.0.1.0/24, 10.0.0.128/25, 192.168.0.0/16 | Format-Table Left, Relation, Right
}
```

Expect: six rows; exactly one is not Disjoint: `10.0.0.0/24 Contains 10.0.0.128/25`.

Pester: "finds a deliberate overlap with -OverlapOnly", "returns one row per pair with the relation read left to right"

### 1.4 Get-NetworkConnection -Resolve on this machine

Live connections with reverse DNS and the cloud each remote address belongs to. Needs network access for the reverse lookups.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    $rows = Get-NetworkConnection -Resolve
    $rows | Where-Object Cloud | Select-Object -First 5 | Format-Table Protocol, RemoteIp, RemotePort, Cloud, Service, Asn, ProcessName
    'Rows {0}, with Cloud {1}, Source {2}' -f $rows.Count, @($rows | Where-Object Cloud).Count, (($rows.Source | Select-Object -Unique) -join ' + ')
}
```

Expect: up to five rows with Cloud filled (Azure, AWS, GCP or Google), a Service such as `AzureFrontDoor.FirstParty` or `Google Cloud`, Asn 8075, 16509 or 15169 and a ProcessName; then a line like `Rows 603, with Cloud 52, Source Get-NetTCPConnection + Get-NetUDPEndpoint` where the Cloud count is at least 1 (counts vary by machine). With a browser or OneDrive running there are always cloud rows. Rerun for 0.1.1: unchanged apart from the counts.

Pester: "adds RemoteHost, Cloud, Service, Asn and Owner with -Resolve", "lists connections with the native tool, with processes" (Live)

### 1.5 Trace-NetworkPath to 1.1.1.1: native and .NET

The same path traced by tracert and by the .NET floor.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    Trace-NetworkPath 1.1.1.1 -Tool Native | Format-Table Hop, Ip, RttMs, LossPercent
    (Trace-NetworkPath 1.1.1.1 -Tool Native -MaxHops 3)[0].Source
    Trace-NetworkPath 1.1.1.1 -Tool DotNet | Format-Table Hop, Ip, RttMs, LossPercent
    (Trace-NetworkPath 1.1.1.1 -Tool DotNet -MaxHops 3)[0].Source
}
```

Expect: two hop tables with the same addresses in the same order, the first hop your gateway (for example 192.168.0.1) and the last `1.1.1.1` with LossPercent 0. A hop where some probes went unanswered keeps a real LossPercent (for example `66.70` with one RTT); a hop that answered no probe while later hops did shows an empty Ip and an empty LossPercent, not 100 (0.1.1). Between them `tracert -d -h 3 -w 1000 1.1.1.1`, and after the second `[System.Net.NetworkInformation.Ping]::new() | ForEach-Object { foreach ($ttl in 1..3) { foreach ($q in 1..3) { $_.Send('1.1.1.1', 1000, [byte[]]::new(32), [System.Net.NetworkInformation.PingOptions]::new($ttl, $true)) } } }  # stops at the first Success`. Native RTTs are whole milliseconds; .NET RTTs have decimals except at the last hop.

Pester: "reads Windows tracert, including a timed-out hop", "a hop that answered no probe while a later hop did: Responded false, LossPercent null, not 100", "a hop where some probes answered keeps its real LossPercent", "runs tracert -d on Windows", "traces 1.1.1.1 with the native tool and the .NET floor" (Live)

### 1.6 ConvertTo-NetworkGraph: node and edge counts from 1.4

Item 1.4's connections as a graph, counted by node kind, edge kind and finding.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    $graph = Get-NetworkConnection -Resolve | ConvertTo-NetworkGraph
    $graph
    $graph.Nodes | Group-Object Kind -NoElement | Sort-Object Name | Format-Table Name, Count
    $graph.Edges | Group-Object Kind -NoElement | Sort-Object Name | Format-Table Name, Count
    $graph.Findings | Group-Object Finding -NoElement | Format-Table Name, Count
}
```

Expect: Root is this computer's name in lower case, with NodeCount, EdgeCount and FindingCount (for example 779, 1762, 82). Node kinds Asn, Cloud, Connection, Host (1), Process, RemoteHost, where Connection equals the row count from 1.4 and Cloud is 1 to 4; edge kinds BelongsTo, ConnectsTo, Contains, OwnedBy, where OwnedBy equals Connection (for example 633 and 633: since 0.1.1 the Connection Id carries the PID, so sockets sharing an endpoint are separate nodes); findings WildcardListener and usually NonCloudPublicConnection.

Pester: "node property names equal the contract in docs/graph-shape.md", "gives every node a unique Id", "reports WildcardListener on testhost/conn/tcp/0.0.0.0:8080/*/1264", "two sockets sharing an endpoint are two Connection nodes, each owned by its process", "graphs the live connections of this host" (Live)

### 1.7 Tab completion of -Cloud

The four clouds complete on `-Cloud`, and narrow as you type.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    $line = 'Get-Subnet 10.0.0.0/24 -Cloud '
    (TabExpansion2 -inputScript $line -cursorColumn $line.Length).CompletionMatches.CompletionText
    $line = 'Get-Subnet 10.0.0.0/24 -Cloud A'
    (TabExpansion2 -inputScript $line -cursorColumn $line.Length).CompletionMatches.CompletionText
}
```

Expect: `AWS`, `Azure`, `GCP`, `None`, then `AWS`, `Azure`. In an interactive shell, typing `Get-Subnet 10.0.0.0/24 -Cloud ` and pressing Tab cycles through the same four.

Pester: "completes -Cloud on Get-Subnet", "completes -Cloud on New-SubnetPlan"

### 1.8 Test-NetworkPort: Auto is the .NET path, Native is still there

A loopback listener tested with the default (Auto) and with `-Tool Native`, then a filtered documentation address timed with the default.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $auto = Test-NetworkPort 127.0.0.1 -Port $port
    $native = Test-NetworkPort 127.0.0.1 -Port $port -Tool Native
    $listener.Stop()
    $auto, $native | Format-List Open, LatencyMs, Source
    (Measure-Command { Test-NetworkPort 192.0.2.1 -Port 443 -Timeout 1000 }).TotalSeconds -lt 3
}
```

Expect: two lists. The first: Open `True`, a LatencyMs (for example `22.3`; the first connect in a process includes .NET start-up), Source `[System.Net.Sockets.TcpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork).ConnectAsync('127.0.0.1', <port>).Wait(2000)`. The second: Open `True`, LatencyMs empty, Source `Test-NetConnection -ComputerName 127.0.0.1 -Port <port>`. Then `True`: the filtered address took the one-second timeout, not Test-NetConnection's twenty seconds.

Pester: "Auto uses the .NET TcpClient path even when the native tool is installed", "returns one row per port with the IANA service and the nc command line", "times each connect from its own start: a slow port 2 does not add to port 1's LatencyMs"

### 1.9 ConvertTo-NetworkGraph: edge kinds are PascalCase

A VLSM plan as a graph: its edges use TerraformGraph's PascalCase kinds, and the 0.1.0 lower-case kind is gone.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    $graph = New-SubnetPlan 10.0.0.0/22 -Hosts 250, 120 -Cloud Azure | ConvertTo-NetworkGraph -HostName testhost
    $graph.Edges | Format-Table From, To, Kind
    $graph.Edges.Kind -ccontains 'contains'
}
```

Expect: two rows, `10.0.0.0/22@Azure 10.0.0.0/24@Azure Contains` and `10.0.0.0/22@Azure 10.0.1.0/25@Azure Contains`, then `False`.

Pester: "edge kinds are PascalCase and the doc table, the module list and TerraformGraph agree", "every edge joins two nodes in the graph and uses a documented kind"

### 1.10 Get-NetworkHost: a third-party firewall is ThirdParty, not Disabled

On a machine whose Windows Firewall profiles are all off and whose firewall is a product registered with Windows Security Center (this machine: Norton Security).

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    $hostInfo = Get-NetworkHost
    $hostInfo | Format-List Firewall, FirewallReason
    $hostInfo.FirewallProducts | Format-Table Name, Enabled, ProductState
}
```

Expect: `Firewall : ThirdParty`, `FirewallReason : Windows Firewall off (Domain off, Private off, Public off); Norton Security registered and enabled in Windows Security Center`, then one row `Norton Security True 331776`. On a machine with Windows Firewall on, Firewall is `Enabled` and FirewallProducts is empty.

Pester: "Windows: every profile off and an enabled product registered is ThirdParty, naming it", "Windows: every profile off and no enabled product is Disabled", "reads SecurityCenter2 FirewallProduct: Norton Security, productState 331776, is enabled", "Linux: reads /etc/ufw/ufw.conf before ufw status, so no root is needed"

### 1.11 ConvertTo-NetworkGraph: rows that came back from a job

Listeners read in this process, sent through a job (which deserializes them), and graphed both ways.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    $rows = @(Get-NetworkConnection -Tool DotNet -Protocol Tcp -State Listen)
    $back = Start-Job -ArgumentList (, $rows) -ScriptBlock { param($Rows) $Rows } | Receive-Job -Wait -AutoRemoveJob
    $back[0].PSObject.TypeNames[0]
    'direct {0} nodes, via job {1} nodes' -f ($rows | ConvertTo-NetworkGraph).NodeCount, ($back | ConvertTo-NetworkGraph).NodeCount
}
```

Expect: `Deserialized.NetworkGraph.Connection`, then `direct 98 nodes, via job 98 nodes` (the count varies by machine; the two numbers are equal and no "skipped" warning appears).

Pester: "graphs rows that came back from a job (Deserialized.* type names) like the direct rows"

### 1.12 Test-IPAddress: Source cites the data a verdict came from

A public address, an Azure address and a private one.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    Test-IPAddress 1.1.1.1, 13.85.16.224, 10.0.0.1 | Format-List Ip, Scope, Cloud, Source
}
```

Expect: 1.1.1.1 Scope `Public`, Cloud empty, Source `special-use.json pulled <date> (https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry-1.csv); cloud-ranges.json.gz pulled <date> (<first cloud source>)`; 13.85.16.224 Scope `Public`, Cloud `Azure`, Source `cloud-ranges.json.gz pulled <date> (https://download.microsoft.com/.../ServiceTags_Public_<date>.json)`; 10.0.0.1 Scope `Private`, Source `[RFC1918]`.

Pester: "calls an ordinary address Public and cites both data files it is absent from", "finds <Cloud> for the first address of a harvested <Cloud> prefix", "each Source is a resolvable verb-noun command, a wrapped tool command line, a full-type-name .NET expression, or a data citation; every command parses"

### 1.13 Trace-NetworkPath: Tool, AvgMs and Responded, and the Hop Id

A trace of loopback with the default tool (the .NET path on Windows), and its Hop node.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    $hops = @(Trace-NetworkPath 127.0.0.1 -MaxHops 3)
    $hops | Format-List Tool, Hop, Ip, RttMs, AvgMs, LossPercent, Responded
    ($hops | ConvertTo-NetworkGraph -HostName testhost).Nodes | Where-Object Kind -eq 'Hop' | Format-Table Id, AvgMs, Responded
}
```

Expect: one hop: Tool `DotNet` (on Windows), Hop `1`, Ip `127.0.0.1`, three RTTs with decimals (for example `{10.969, 0.52, 0.311}`), AvgMs their mean (`3.933`), LossPercent `0`, Responded `True`; then one node `hop/127.0.0.1/DotNet/1` with the same AvgMs and Responded `True`.

Pester: "takes the .NET path even with tracert installed", "a native and a .NET trace of the same target are two chains", "node property names equal the contract in docs/graph-shape.md"

### 1.14 Get-ExternalIpAddress -Rdap: one command per answer, the RDAP request, and a Cidr that holds the address

Needs network access (ipify, AWS checkip, icanhazip, rdap.org). The address itself is not part of the Expect.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    $result = Get-ExternalIpAddress -Rdap
    $result.Answers | Format-Table Endpoint, Error, Source -Wrap
    $result | Format-List Agreed, Network, Cidr, RdapSource, Source
    if ($result.Cidr) { 'Cidr holds Ip: ' + ((Test-SubnetOverlap -Cidr $result.Cidr, "$($result.Ip)/32").Relation -eq 'Contains') }
}
```

Expect: three answer rows (ipify, aws-checkip, icanhazip) with no Error, each Source one curl command line (`curl -s -S --proto =https -m 10 https://api.ipify.org?format=json`, and so on); then Agreed `True`, your registry's Network name, a Cidr, RdapSource `Invoke-WebRequest -Uri 'https://rdap.org/ip/<your address>' -MaximumRedirection 5 -TimeoutSec 60`, Source `Get-ExternalIpAddress -Rdap -TimeoutSec 10 -Tool Native`; then `Cidr holds Ip: True`.

Pester: "adds registration data from RDAP through rdap.org, with the CIDR block that holds the address", "leaves Cidr empty with a warning when no RDAP block holds the address", "asks every endpoint in ip-sources.json and reports agreement", "asks the real endpoints and RDAP" (Live)
