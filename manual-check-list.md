# NetworkGraph manual check list

Module version: 0.2.0
Last updated: 2026-10-08

Every block runs in the shell it is pasted into: it moves to the repository, removes any loaded NetworkGraph and imports the module from `src` with `-Force`, so no item depends on another or picks up an installed NetworkGraph. No block wraps itself in `pwsh -Command { ... }`, which prints nothing when pasted into a console. Objects keep their default views, and the Expect lines describe what those look like. Items are append-only: never renumber, mark a removed item "(removed in x.y.z)".

Layout: section 0 is setup, section 1 the first checks (the README's examples and cross-cutting behaviour), sections 2 to 24 one exported function each in FunctionsToExport order, one item per parameter set or distinct behaviour. From section 25 on, a section covers a family of functions or one release's cross-cutting contracts. Items 1.4, 1.5, 1.6, 1.14, 11.x, 18.1, 18.2 and 24.1 need network access; the rest do not.

Verified for 0.2.0: items 0.1, 14.1 to 14.3, 15.1, 16.1, 16.2, 22.1 and 22.2 were rerun, and 25.1 and 25.2 added and run, each block saved to a temp `.ps1` and run with `pwsh -NoProfile -File` on Windows 11 (PowerShell 7.6.6) on 2026-10-08; their Expect lines are written from that output. Verified for 0.1.1, blocks run in the pasted shell (every item): each block was saved to a temp `.ps1` and run with `pwsh -NoProfile -File` on Windows 11 (PowerShell 7.6.6) on 2026-10-07, with network access and no nmap or dig on PATH; Expect lines 1.1, 1.5, 1.6 and 1.8 were rewritten from that output, the rest matched. Verified for 0.1.1 (sections 2 to 24): every item was run on Windows 11 (PowerShell 7.6.6) on 2026-10-07, with no nmap or dig on PATH, and its Expect line written from that output. Verified for 0.1.1: items 0.1, 1.4, 1.5, 1.6 and 1.8 were rerun, and 1.10 to 1.14 added and run, on Windows 11 (PowerShell 7.6.6); their Expect lines are written from that output. Verified for 0.1.0: every item below was run on Windows 11 (PowerShell 7.6.6) and its Expect line written from that output. Items 1.1, 1.2, 1.3 and 1.7 were also run on Linux (Ubuntu 22.04 container, PowerShell 7, with the repository path changed to the container's) with the same output; 1.4, 1.5 and 1.6 depend on the host's own connections and path and were exercised on Linux through the Live Pester tests, not by these blocks.

## 0 Setup

### 0.1 Fresh import: version and exports

Imports the module from source and lists its version and exported commands.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
(Get-Module NetworkGraph).Version.ToString()
(Get-Command -Module NetworkGraph).Count
(Get-Command -Module NetworkGraph).Name -join ', '
```

Expect: `0.2.0`, then `23`, then ConvertFrom-SubnetMask, ConvertTo-NetworkGraph, ConvertTo-SubnetMask, Get-ExternalIpAddress, Get-MacAddressVendor, Get-NetworkConnection, Get-NetworkGraphData, Get-NetworkHost, Get-NetworkInterface, Get-NetworkNeighbor, Get-NetworkRoute, Get-Subnet, Get-SubnetChildren, Get-SubnetParent, Invoke-NetworkScan, New-SubnetPlan, Resolve-NetworkName, Test-IPAddress, Test-NetworkPath, Test-NetworkPort, Test-SubnetOverlap, Trace-NetworkPath, Update-NetworkGraphData.

Pester: "is version 0.2.0 and needs PowerShell 7.4", "psd1 exports match Public/", "exports 23 functions in three groups by noun", "every Public file exports exactly its function name"

## 1 First checks

### 1.1 Get-Subnet: Azure /24

An Azure /24 with its five reserved addresses.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$subnet = Get-Subnet 10.0.0.0/24 -Cloud Azure
$subnet
$subnet.Reserved | Format-Table Ip, Role
```

Expect: the default view, a list with Cidr `10.0.0.0/24`, Cloud `Azure`, FirstUsable `10.0.0.4`, LastUsable `10.0.0.254`, Usable `251`, Gateway `10.0.0.1`; then five rows: 10.0.0.0 Network address, 10.0.0.1 Default gateway, 10.0.0.2 Azure DNS mapping, 10.0.0.3 Azure DNS mapping, 10.0.0.255 Broadcast address.

Pester: "Azure /24 has 251 usable and 5 reserved rows", "Azure /24 reserves .0, .1, .2, .3 and .255 with their roles"

### 1.2 New-SubnetPlan: VLSM

Four subnets fitted largest first into a /22, then the same hosts failing a /23 under Azure.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$plan = New-SubnetPlan 10.0.0.0/22 -Hosts 250, 120, 60, 25
$plan.Subnets | Format-Table Name, Cidr, RequestedHosts, Usable
$plan.Remaining
try { New-SubnetPlan 10.0.0.0/23 -Hosts 250, 120, 60, 25 -Cloud Azure } catch { $_.Exception.Message }
```

Expect: subnet-1 10.0.0.0/24 (250, 254 usable), subnet-2 10.0.1.0/25 (120, 126), subnet-3 10.0.1.128/26 (60, 62), subnet-4 10.0.1.192/27 (25, 30); Remaining `10.0.1.224/27` and `10.0.2.0/23`; then `Plan does not fit: 544 addresses needed (subnet-1 /24, subnet-2 /25, subnet-3 /25, subnet-4 /27), 10.0.0.0/23 has 512 under Azure; short by 32 addresses. Use a larger parent prefix or fewer hosts.`

Pester: "fits the VLSM example (250, 120, 60, 25 hosts) in a /22 with None", "fails the same example in a /23 with Azure and names the shortfall"

### 1.3 Test-SubnetOverlap: a deliberate overlap

Four prefixes, one of which (10.0.0.128/25) sits inside another.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Test-SubnetOverlap 10.0.0.0/24, 10.0.1.0/24, 10.0.0.128/25, 192.168.0.0/16 | Format-Table Left, Relation, Right
```

Expect: six rows; exactly one is not Disjoint: `10.0.0.0/24 Contains 10.0.0.128/25`.

Pester: "finds a deliberate overlap with -OverlapOnly", "returns one row per pair with the relation read left to right"

### 1.4 Get-NetworkConnection -Resolve on this machine

Live connections with reverse DNS and the cloud each remote address belongs to. Needs network access for the reverse lookups.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$rows = Get-NetworkConnection -Resolve
$rows | Where-Object Cloud | Select-Object -First 5 | Format-Table Protocol, RemoteIp, RemotePort, Cloud, Service, Asn, ProcessName
'Rows {0}, with Cloud {1}, Source {2}' -f $rows.Count, @($rows | Where-Object Cloud).Count, (($rows.Source | Select-Object -Unique) -join ' + ')
```

Expect: up to five rows with Cloud filled (Azure, AWS, GCP or Google), a Service such as `AzureFrontDoor.FirstParty` or `Google Cloud`, Asn 8075, 16509 or 15169 and a ProcessName; then a line like `Rows 603, with Cloud 52, Source Get-NetTCPConnection + Get-NetUDPEndpoint` where the Cloud count is at least 1 (counts vary by machine). With a browser or OneDrive running there are always cloud rows. Rerun for 0.1.1: unchanged apart from the counts.

Pester: "adds RemoteHost, Cloud, Service, Asn and Owner with -Resolve", "lists connections with the native tool, with processes" (Live)

### 1.5 Trace-NetworkPath to 1.1.1.1: native and .NET

The same path traced by tracert and by the .NET floor.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Trace-NetworkPath 1.1.1.1 -Tool Native | Format-Table Hop, Ip, RttMs, LossPercent
(Trace-NetworkPath 1.1.1.1 -Tool Native -MaxHops 3)[0].Source
Trace-NetworkPath 1.1.1.1 -Tool DotNet | Format-Table Hop, Ip, RttMs, LossPercent
(Trace-NetworkPath 1.1.1.1 -Tool DotNet -MaxHops 3)[0].Source
```

Expect: two hop tables with the same addresses in the same order (a hop that answered no probe in one trace may answer in the other), the first hop your gateway (for example 192.168.0.1) and the last `1.1.1.1` with LossPercent `0.00`. A hop where some probes went unanswered keeps a real LossPercent (for example `66.70` with one RTT); a hop that answered no probe while later hops did shows an empty Ip and an empty LossPercent, not 100 (0.1.1). Between them `tracert -d -h 3 -w 1000 1.1.1.1`, and after the second `[System.Net.NetworkInformation.Ping]::new() | ForEach-Object { foreach ($ttl in 1..3) { foreach ($q in 1..3) { $_.Send('1.1.1.1', 1000, [byte[]]::new(32), [System.Net.NetworkInformation.PingOptions]::new($ttl, $true)) } } }  # stops at the first Success`. Native RTTs are whole milliseconds; .NET RTTs have decimals except at the last hop.

Pester: "reads Windows tracert, including a timed-out hop", "a hop that answered no probe while a later hop did: Responded false, LossPercent null, not 100", "a hop where some probes answered keeps its real LossPercent", "runs tracert -d on Windows", "traces 1.1.1.1 with the native tool and the .NET floor" (Live)

### 1.6 ConvertTo-NetworkGraph: node and edge counts from 1.4

Item 1.4's connections as a graph, counted by node kind, edge kind and finding.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$graph = Get-NetworkConnection -Resolve | ConvertTo-NetworkGraph
$graph
$graph.Nodes | Group-Object Kind -NoElement | Sort-Object Name | Format-Table Name, Count
$graph.Edges | Group-Object Kind -NoElement | Sort-Object Name | Format-Table Name, Count
$graph.Findings | Group-Object Finding -NoElement | Format-Table Name, Count
```

Expect: a one-row table: Root is this computer's name in lower case, with NodeCount, EdgeCount and FindingCount (for example 568, 1175, 83). Node kinds Asn, Cloud, Connection, Host (1), Process, RemoteHost, where Connection equals the row count from 1.4 and Cloud is 1 to 4; edge kinds BelongsTo, ConnectsTo, Contains, OwnedBy, where OwnedBy equals Connection (for example 439 and 439: since 0.1.1 the Connection Id carries the PID, so sockets sharing an endpoint are separate nodes); findings WildcardListener and usually NonCloudPublicConnection.

Pester: "node property names equal the contract in docs/graph-shape.md", "gives every node a unique Id", "reports WildcardListener on testhost/conn/tcp/0.0.0.0:8080/*/1264", "two sockets sharing an endpoint are two Connection nodes, each owned by its process", "graphs the live connections of this host" (Live)

### 1.7 Tab completion of -Cloud

The four clouds complete on `-Cloud`, and narrow as you type.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$line = 'Get-Subnet 10.0.0.0/24 -Cloud '
(TabExpansion2 -inputScript $line -cursorColumn $line.Length).CompletionMatches.CompletionText
$line = 'Get-Subnet 10.0.0.0/24 -Cloud A'
(TabExpansion2 -inputScript $line -cursorColumn $line.Length).CompletionMatches.CompletionText
```

Expect: `AWS`, `Azure`, `GCP`, `None`, then `AWS`, `Azure`. In an interactive shell, typing `Get-Subnet 10.0.0.0/24 -Cloud ` and pressing Tab cycles through the same four.

Pester: "completes -Cloud on Get-Subnet", "completes -Cloud on New-SubnetPlan"

### 1.8 Test-NetworkPort: Auto is the .NET path, Native is still there

A loopback listener tested with the default (Auto) and with `-Tool Native`, then a filtered documentation address timed with the default.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$auto = Test-NetworkPort 127.0.0.1 -Port $port
$native = Test-NetworkPort 127.0.0.1 -Port $port -Tool Native
$listener.Stop()
$auto, $native | Format-List Open, LatencyMs, Source
(Measure-Command { Test-NetworkPort 192.0.2.1 -Port 443 -Timeout 1000 }).TotalSeconds -lt 3
```

Expect: two lists. The first: Open `True`, a LatencyMs (for example `18.9`; the first connect in a shell includes .NET start-up), Source `[System.Net.Sockets.TcpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork).ConnectAsync('127.0.0.1', <port>).Wait(2000)`. The second: Open `True`, LatencyMs empty, Source `Test-NetConnection -ComputerName 127.0.0.1 -Port <port>`. Then `True`: the filtered address took the one-second timeout, not Test-NetConnection's twenty seconds.

Pester: "Auto uses the .NET TcpClient path even when the native tool is installed", "returns one row per port with the IANA service and the nc command line", "times each connect from its own start: a slow port 2 does not add to port 1's LatencyMs"

### 1.9 ConvertTo-NetworkGraph: edge kinds are PascalCase

A VLSM plan as a graph: its edges use TerraformGraph's PascalCase kinds, and the 0.1.0 lower-case kind is gone.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$graph = New-SubnetPlan 10.0.0.0/22 -Hosts 250, 120 -Cloud Azure | ConvertTo-NetworkGraph -HostName testhost
$graph.Edges | Format-Table From, To, Kind
$graph.Edges.Kind -ccontains 'contains'
```

Expect: two rows, `10.0.0.0/22@Azure 10.0.0.0/24@Azure Contains` and `10.0.0.0/22@Azure 10.0.1.0/25@Azure Contains`, then `False`.

Pester: "edge kinds are PascalCase and the doc table, the module list and TerraformGraph agree", "every edge joins two nodes in the graph and uses a documented kind"

### 1.10 Get-NetworkHost: a third-party firewall is ThirdParty, not Disabled

On a machine whose Windows Firewall profiles are all off and whose firewall is a product registered with Windows Security Center (this machine: Norton Security).

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$hostInfo = Get-NetworkHost
$hostInfo | Format-List Firewall, FirewallReason
$hostInfo.FirewallProducts | Format-Table Name, Enabled, ProductState
```

Expect: `Firewall : ThirdParty`, `FirewallReason : Windows Firewall off (Domain off, Private off, Public off); Norton Security registered and enabled in Windows Security Center`, then one row `Norton Security True 331776`. On a machine with Windows Firewall on, Firewall is `Enabled` and FirewallProducts is empty.

Pester: "Windows: every profile off and an enabled product registered is ThirdParty, naming it", "Windows: every profile off and no enabled product is Disabled", "reads SecurityCenter2 FirewallProduct: Norton Security, productState 331776, is enabled", "Linux: reads /etc/ufw/ufw.conf before ufw status, so no root is needed"

### 1.11 ConvertTo-NetworkGraph: rows that came back from a job

Listeners read in this process, sent through a job (which deserializes them), and graphed both ways.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$rows = @(Get-NetworkConnection -Tool DotNet -Protocol Tcp -State Listen)
$back = Start-Job -ArgumentList (, $rows) -ScriptBlock { param($Rows) $Rows } | Receive-Job -Wait -AutoRemoveJob
$back[0].PSObject.TypeNames[0]
'direct {0} nodes, via job {1} nodes' -f ($rows | ConvertTo-NetworkGraph).NodeCount, ($back | ConvertTo-NetworkGraph).NodeCount
```

Expect: `Deserialized.NetworkGraph.Connection`, then `direct 98 nodes, via job 98 nodes` (the count varies by machine; the two numbers are equal and no "skipped" warning appears).

Pester: "graphs rows that came back from a job (Deserialized.* type names) like the direct rows"

### 1.12 Test-IPAddress: Source cites the data a verdict came from

A public address, an Azure address and a private one.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Test-IPAddress 1.1.1.1, 13.85.16.224, 10.0.0.1 | Format-List Ip, Scope, Cloud, Source
```

Expect: 1.1.1.1 Scope `Public`, Cloud empty, Source `special-use.json pulled <date> (https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry-1.csv); cloud-ranges.json.gz pulled <date> (<first cloud source>)`; 13.85.16.224 Scope `Public`, Cloud `Azure`, Source `cloud-ranges.json.gz pulled <date> (https://download.microsoft.com/.../ServiceTags_Public_<date>.json)`; 10.0.0.1 Scope `Private`, Source `[RFC1918]`.

Pester: "calls an ordinary address Public and cites both data files it is absent from", "finds <Cloud> for the first address of a harvested <Cloud> prefix", "each Source is a resolvable verb-noun command, a wrapped tool command line, a full-type-name .NET expression, or a data citation; every command parses"

### 1.13 Trace-NetworkPath: Tool, AvgMs and Responded, and the Hop Id

A trace of loopback with the default tool (the .NET path on Windows), and its Hop node.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$hops = @(Trace-NetworkPath 127.0.0.1 -MaxHops 3)
$hops | Format-List Tool, Hop, Ip, RttMs, AvgMs, LossPercent, Responded
($hops | ConvertTo-NetworkGraph -HostName testhost).Nodes | Where-Object Kind -eq 'Hop' | Format-Table Id, AvgMs, Responded
```

Expect: one hop: Tool `DotNet` (on Windows), Hop `1`, Ip `127.0.0.1`, three RTTs with decimals (for example `{10.969, 0.52, 0.311}`), AvgMs their mean (`3.933`), LossPercent `0`, Responded `True`; then one node `hop/127.0.0.1/DotNet/1` with the same AvgMs and Responded `True`.

Pester: "takes the .NET path even with tracert installed", "a native and a .NET trace of the same target are two chains", "node property names equal the contract in docs/graph-shape.md"

### 1.14 Get-ExternalIpAddress -Rdap: one command per answer, the RDAP request, and a Cidr that holds the address

Needs network access (ipify, AWS checkip, icanhazip, rdap.org). The address itself is not part of the Expect.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$result = Get-ExternalIpAddress -Rdap
$result.Answers | Format-Table Endpoint, Error, Source -Wrap
$result | Format-List Agreed, Network, Cidr, RdapSource, Source
if ($result.Cidr) { 'Cidr holds Ip: ' + ((Test-SubnetOverlap -Cidr $result.Cidr, "$($result.Ip)/32").Relation -eq 'Contains') }
```

Expect: three answer rows (ipify, aws-checkip, icanhazip) with no Error, each Source one curl command line (`curl -s -S --proto =https -m 10 https://api.ipify.org?format=json`, and so on); then Agreed `True`, your registry's Network name, a Cidr, RdapSource `Invoke-WebRequest -Uri 'https://rdap.org/ip/<your address>' -MaximumRedirection 5 -TimeoutSec 60`, Source `Get-ExternalIpAddress -Rdap -TimeoutSec 10 -Tool Native`; then `Cidr holds Ip: True`.

Pester: "adds registration data from RDAP through rdap.org, with the CIDR block that holds the address", "leaves Cidr empty with a warning when no RDAP block holds the address", "asks every endpoint in ip-sources.json and reports agreement", "asks the real endpoints and RDAP" (Live)

## 2 ConvertFrom-SubnetMask

### 2.1 ConvertFrom-SubnetMask: -Mask

Three dotted masks to prefix lengths, from the pipeline.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
'255.255.255.192', '255.255.0.0', '255.255.255.255' | ConvertFrom-SubnetMask
```

Expect: Three lines: `26`, `16`, `32`.

Pester: "converts <Mask> to /<Length>", "round-trips every IPv4 length"

### 2.2 ConvertFrom-SubnetMask: a non-contiguous mask

A mask whose one bits have a gap is refused.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
try { ConvertFrom-SubnetMask 255.0.255.0 } catch { $_.Exception.Message }
```

Expect: `'255.0.255.0' is not a valid mask: its one bits are not contiguous from the left.`

Pester: "rejects a non-contiguous mask"

## 3 ConvertTo-SubnetMask

### 3.1 ConvertTo-SubnetMask: -PrefixLength

Three prefix lengths to dotted masks, from the pipeline.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
26, 16, 32 | ConvertTo-SubnetMask
```

Expect: Three lines: `255.255.255.192`, `255.255.0.0`, `255.255.255.255`.

Pester: "converts /<Length> to <Mask>", "takes PrefixLength from the pipeline"

### 3.2 ConvertTo-SubnetMask: an IPv6 prefix length

A length above 32 has no dotted mask.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
try { ConvertTo-SubnetMask 33 } catch { $_.Exception.Message }
```

Expect: `Prefix length 33 is IPv6: IPv6 has no dotted subnet mask, use the prefix length (/33) itself.`

Pester: "gives a clear error for an IPv6 prefix length"

## 4 Get-MacAddressVendor

### 4.1 Get-MacAddressVendor: -MacAddress in three notations

Hyphen, colon and Cisco dot notation, each looked up in the IEEE OUI data.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-MacAddressVendor 00-15-5D-01-02-03, 00:1A:2B:3C:4D:5E, 001b.6300.0001 | Format-Table MacAddress, Vendor, IsLocallyAdministered, IsMulticast
```

Expect: Three rows, each MacAddress in hyphen form: `00-15-5D-01-02-03 Microsoft Corporation`, `00-1A-2B-3C-4D-5E Ayecom Technology Co., Ltd.`, `00-1B-63-00-00-01 Apple, Inc.`, all with IsLocallyAdministered and IsMulticast `False`. (Vendor names come from oui.json; a refreshed harvest may spell them differently.)

Pester: "reads <Mac> in any notation"

### 4.2 Get-MacAddressVendor: randomised, multicast and invalid addresses

A locally-administered (randomised) MAC names no vendor, a multicast MAC says so, and text that is not a MAC is a non-terminating error.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-MacAddressVendor 02-15-5D-01-02-03, 01-00-5E-00-00-FB | Format-Table MacAddress, Vendor, IsLocallyAdministered, IsMulticast
Get-MacAddressVendor not-a-mac 2>&1 | ForEach-Object { "$_" }
```

Expect: Two rows with an empty Vendor: `02-15-5D-01-02-03` IsLocallyAdministered `True`, `01-00-5E-00-00-FB` IsMulticast `True`; then `'not-a-mac' is not a MAC address (six bytes, for example 00-1A-2B-3C-4D-5E).`

Pester: "gives no vendor for a locally-administered (randomised) address", "reads the multicast bit", "writes an error for text that is not a MAC address and goes on"

## 5 Get-Subnet

### 5.1 Get-Subnet: -Cidr (default set, no cloud)

Host bits are cleared and the plain (None) rules apply.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-Subnet 10.0.0.77/26 | Format-List Cidr, Network, Broadcast, FirstUsable, LastUsable, Usable, Mask, Cloud
```

Expect: Cidr `10.0.0.64/26`, Network `10.0.0.64`, Broadcast `10.0.0.127`, FirstUsable `10.0.0.65`, LastUsable `10.0.0.126`, Usable `62`, Mask `255.255.255.192`, Cloud `None`.

Pester: "clears host bits: 10.0.0.77/26 is 10.0.0.64/26", "<Cidr> has <Usable> usable from <First> to <Last>"

### 5.2 Get-Subnet: -Address -Mask

The Mask parameter set: an address and a dotted mask.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-Subnet -Address 192.168.1.77 -Mask 255.255.255.192 | Format-List Cidr, FirstUsable, LastUsable, Usable
```

Expect: Cidr `192.168.1.64/26`, FirstUsable `192.168.1.65`, LastUsable `192.168.1.126`, Usable `62`.

Pester: "takes -Address with -PrefixLength or -Mask"

### 5.3 Get-Subnet: -Address -PrefixLength -Cloud GCP

The PrefixLength parameter set, with GCP's reservations (the first two, the second-to-last and the last).

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-Subnet -Address 172.16.5.9 -PrefixLength 20 -Cloud GCP | Format-List Cidr, FirstUsable, LastUsable, Usable, Gateway
(Get-Subnet -Address 172.16.5.9 -PrefixLength 20 -Cloud GCP).Reserved | Format-Table Ip, Role
```

Expect: Cidr `172.16.0.0/20`, FirstUsable `172.16.0.2`, LastUsable `172.16.15.253`, Usable `4092`, Gateway `172.16.0.1`; then four rows: 172.16.0.0 Network address, 172.16.0.1 Default gateway, 172.16.15.254 Reserved for potential future use (second-to-last), 172.16.15.255 Broadcast address.

Pester: "takes -Address with -PrefixLength or -Mask", "GCP reserves the second-to-last address"

### 5.4 Get-Subnet: below the cloud minimum

A /29 under AWS (minimum /28) is flagged and warned about, not refused.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-Subnet 10.0.0.0/29 -Cloud AWS 3>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.WarningRecord]) { "WARNING: $_" } else { $_ | Format-List Cidr, Usable, BelowCloudMinimum } }
```

Expect: `WARNING: 10.0.0.0/29 is smaller than the AWS minimum subnet /28.`, then Cidr `10.0.0.0/29`, Usable `3`, BelowCloudMinimum `True`.

Pester: "flags a subnet below the cloud minimum and warns"

### 5.5 Get-Subnet: an invalid prefix

A prefix length out of range for IPv4 is a terminating error.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
try { Get-Subnet 10.0.0.0/33 } catch { $_.Exception.Message }
```

Expect: `Prefix length 33 is out of range for IPv4 (0-32).`

Pester: "rejects text that is not a prefix"

## 6 Get-SubnetChildren

### 6.1 Get-SubnetChildren: -Cidr -In

Direct children only: 10.0.1.128/25 sits under 10.0.1.0/24, so it is not a direct child of the /16.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-SubnetChildren 10.0.0.0/16 -In 10.0.1.0/24, 10.0.1.128/25, 10.1.0.0/24 | Format-Table Parent, Cidr
```

Expect: One row: Parent `10.0.0.0/16`, Cidr `10.0.1.0/24`.

Pester: "returns only direct children by default"

### 6.2 Get-SubnetChildren: -Cidr -In -Recurse

Every descendant, each with its direct parent.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-SubnetChildren 10.0.0.0/16 -In 10.0.1.0/24, 10.0.1.128/25, 10.1.0.0/24 -Recurse | Format-Table Parent, Cidr
```

Expect: Two rows: `10.0.0.0/16 10.0.1.0/24` and `10.0.1.0/24 10.0.1.128/25`. 10.1.0.0/24 is in neither.

Pester: "returns every descendant with its direct parent with -Recurse"

## 7 Get-SubnetParent

### 7.1 Get-SubnetParent: -Cidr (the list itself)

Without -In, each prefix's parent is the most specific other prefix in the same list.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-SubnetParent 10.0.1.0/24, 10.0.0.0/16, 10.0.1.128/25 | Format-Table Cidr, Parent
```

Expect: Three rows: `10.0.1.0/24 10.0.0.0/16`, `10.0.0.0/16` with an empty Parent, `10.0.1.128/25 10.0.1.0/24`.

Pester: "finds the most specific containing prefix within the list itself", "returns no parent for a prefix outside every candidate, and never itself"

### 7.2 Get-SubnetParent: -Cidr -In

A bare address placed among candidate prefixes.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-SubnetParent 10.0.1.7 -In 10.0.0.0/16, 10.0.1.0/24 | Format-Table Cidr, Parent
```

Expect: One row: Cidr `10.0.1.7/32`, Parent `10.0.1.0/24`.

Pester: "places a bare address among -In candidates"

## 8 New-SubnetPlan

### 8.1 New-SubnetPlan: -Hosts -Cloud AWS

The Hosts set under AWS: reservations are added before rounding up, and no subnet goes below the /28 minimum.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$plan = New-SubnetPlan 10.0.0.0/24 -Hosts 60, 2 -Cloud AWS
$plan.Subnets | Format-Table Name, Cidr, RequestedHosts, Usable
$plan.Remaining
```

Expect: `subnet-1 10.0.0.0/25 60 123` and `subnet-2 10.0.0.128/28 2 11`; Remaining `10.0.0.144/28`, `10.0.0.160/27`, `10.0.0.192/26`.

Pester: "adds the cloud reservations before rounding up (60 hosts is a /26 under None, a /25 under Azure)", "never goes below the cloud minimum (2 hosts is a /28 under AWS)"

### 8.2 New-SubnetPlan: -PrefixLength (Equal set)

An equal split into /26s under Azure, then a split length shorter than the parent.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$plan = New-SubnetPlan 10.0.0.0/24 -PrefixLength 26 -Cloud Azure
$plan.Subnets | Format-Table Name, Cidr, Usable, FirstUsable, LastUsable
try { New-SubnetPlan 10.0.0.0/24 -PrefixLength 23 } catch { $_.Exception.Message }
```

Expect: Four rows subnet-1 to subnet-4, `10.0.0.0/26`, `10.0.0.64/26`, `10.0.0.128/26`, `10.0.0.192/26`, each Usable `59`, the first FirstUsable `10.0.0.4` and LastUsable `10.0.0.62`; then `Cannot split 10.0.0.0/24 into /23 subnets: the length must be between 24 and 32.`

Pester: "splits equally with -PrefixLength", "rejects an equal split shorter than the parent"

### 8.3 New-SubnetPlan: -Requirement (named subnets)

The Requirement set: a hashtable of names to host counts, placed largest first.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$plan = New-SubnetPlan 10.1.0.0/16 -Requirement @{ web = 200; app = 400 } -Cloud Azure
$plan.Subnets | Format-Table Name, Cidr, RequestedHosts, Usable
```

Expect: Two rows: `app 10.1.0.0/23 400 507` then `web 10.1.2.0/24 200 251`.

Pester: "names subnets from -Requirement", "places largest first whatever order the hosts are given in, keeping names"

## 9 Test-IPAddress

### 9.1 Test-IPAddress: special-use addresses

One address from each common special-use block, with the registry row and RFC it came from.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Test-IPAddress 10.0.0.1, 100.64.0.1, 169.254.1.1, 127.0.0.1, 224.0.0.251, 192.0.2.10 | Format-Table Ip, Scope, SpecialUse, Source
```

Expect: Six rows: 10.0.0.1 Private Private-Use `[RFC1918]`; 100.64.0.1 Cgnat Shared Address Space `[RFC6598]`; 169.254.1.1 LinkLocal Link Local `[RFC3927]`; 127.0.0.1 Loopback Loopback `[RFC1122], Section 3.2.1.3`; 224.0.0.251 Multicast Multicast `[RFC5771]`; 192.0.2.10 Documentation Documentation (TEST-NET-1) `[RFC5737]`.

Pester: "classifies one address in every special-use row by that row", "sets the flags for <Ip>"

## 10 Test-SubnetOverlap

### 10.1 Test-SubnetOverlap: -Cidr, with and without -OverlapOnly

Every pair, then only the pairs that share addresses.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Test-SubnetOverlap 10.0.0.0/24, 10.0.0.128/25, 10.1.0.0/16 | Format-Table Left, Relation, Right
Test-SubnetOverlap 10.0.0.0/24, 10.0.0.128/25, 10.1.0.0/16 -OverlapOnly | Format-Table Left, Relation, Right
```

Expect: Three rows: `10.0.0.0/24 Contains 10.0.0.128/25`, `10.0.0.0/24 Disjoint 10.1.0.0/16`, `10.0.0.128/25 Disjoint 10.1.0.0/16`; then one row, `10.0.0.0/24 Contains 10.0.0.128/25`.

Pester: "returns one row per pair with the relation read left to right", "finds a deliberate overlap with -OverlapOnly"

## 11 Get-ExternalIpAddress

### 11.1 Get-ExternalIpAddress: default (Auto)

This host's public address, asked of every endpoint in ip-sources.json. Needs network access; the address itself is not part of the Expect.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$result = Get-ExternalIpAddress
$result | Format-List Agreed, Source
$result.Answers.Endpoint -join ', '
```

Expect: Agreed `True`, Source `Get-ExternalIpAddress -TimeoutSec 10 -Tool Native` (curl is on PATH on Windows 10 and later); then `ipify, aws-checkip, icanhazip`.

Pester: "asks every endpoint in ip-sources.json and reports agreement", "uses curl when it is the chosen tool", "asks the real endpoints and RDAP" (Live)

### 11.2 Get-ExternalIpAddress: -Tool DotNet -TimeoutSec

The .NET floor (HttpClient through Invoke-WebRequest) with a shorter timeout. Needs network access.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$result = Get-ExternalIpAddress -Tool DotNet -TimeoutSec 5
$result | Format-List Agreed, Source
$result.Answers[0].Source
```

Expect: Agreed `True`, Source `Get-ExternalIpAddress -TimeoutSec 5 -Tool DotNet`; then `Invoke-WebRequest -Uri 'https://api.ipify.org?format=json' -MaximumRedirection 5 -TimeoutSec 5`.

Pester: "asks every endpoint in ip-sources.json and reports agreement", "keeps going when one endpoint fails"

## 12 Get-NetworkConnection

### 12.1 Get-NetworkConnection: -Protocol -State

TCP listeners only, with the native tool (Get-NetTCPConnection on Windows).

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$rows = @(Get-NetworkConnection -Protocol Tcp -State Listen)
$rows | Select-Object -First 3 | Format-Table Protocol, LocalIp, LocalPort, State, ProcessName
'Rows {0}, states {1}, Source {2}' -f $rows.Count, (($rows.State | Select-Object -Unique) -join ','), (($rows.Source | Select-Object -Unique) -join ' + ')
```

Expect: Up to three Tcp Listen rows with a LocalPort and a ProcessName (for example `services`, `System`, `svchost`); then a line like `Rows 66, states Listen, Source Get-NetTCPConnection` (the count varies by machine; the only state is Listen).

Pester: "filters by -State", "always runs ss -tunap (ss -tnap drops the Netid column) and filters -Protocol after", "maps Get-NetTCPConnection objects"

### 12.2 Get-NetworkConnection: -Tool DotNet

The .NET floor, which has no process information and says so in Source.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$rows = @(Get-NetworkConnection -Tool DotNet)
'Rows {0}, with a process {1}' -f $rows.Count, @($rows | Where-Object ProcessId).Count
($rows.Source | Select-Object -Unique) -join "`n"
```

Expect: A line like `Rows 305, with a process 0` (the count varies; the second number is always 0), then the three IPGlobalProperties calls (`GetActiveTcpListeners()`, `GetActiveTcpConnections()`, `GetActiveUdpListeners()`), each ending `# .NET floor: no process information`.

Pester: "lists a loopback listener with no process and says so in Source"

## 13 Get-NetworkHost

### 13.1 Get-NetworkHost: default (Auto)

A summary of this host with the native tools.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-NetworkHost | Format-List HostName, Os, Firewall, Source
```

Expect: HostName is this computer's name, Os `Microsoft Windows 10.0.<build>`, Firewall `Enabled`, `Partial`, `Disabled` or `ThirdParty` (see 1.10), Source `[System.Net.Dns]::GetHostName(); Get-NetIPConfiguration -All; Get-NetRoute; Get-NetFirewallProfile; Get-CimInstance -Namespace root/SecurityCenter2 -ClassName FirewallProduct`.

Pester: "summarises this host with the native tools" (Live), "reads Get-NetFirewallProfile: every profile off is Disabled", "reads a mix of profiles as Partial"

### 13.2 Get-NetworkHost: -Tool DotNet

The same summary with interfaces and routes from the .NET floor; the firewall is still read with the native cmdlets, since .NET has no firewall API.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-NetworkHost -Tool DotNet | Format-List HostName, Os, Firewall, FirewallReason, Source
```

Expect: The same HostName, Os and Firewall as 13.1, a FirewallReason, and a Source that starts `[System.Net.Dns]::GetHostName(); [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces();` and says `# .NET floor: routes derived from addresses and gateways, no route table`.

Pester: "summarises this host on the .NET floor" (Live)

## 14 Get-NetworkInterface

### 14.1 Get-NetworkInterface: default (Auto)

Adapters from Get-NetIPConfiguration, with their InterfaceKey (the interface GUID), addresses and gateways.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$rows = @(Get-NetworkInterface)
$rows | Where-Object Status -eq 'Up' | Select-Object -First 3 | Format-Table Name, InterfaceKey, Status, Ip, PrefixLength, Gateway
'Rows {0}, Source {1}' -f $rows.Count, (($rows.Source | Select-Object -Unique) -join ' + ')
```

Expect: Up to three Up adapters, each with a different InterfaceKey that is a GUID in braces (for example `Wi-Fi {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx} Up {192.168.0.6} {24} {192.168.0.1}`), then a line like `Rows 9, Source Get-NetIPConfiguration -All`.

Pester: "maps Get-NetIPConfiguration (flattened) objects", "keys each Get-NetIPConfiguration interface on its InterfaceGuid, not its alias", "names the cmdlet in Source, looks up the vendor and carries InterfaceKey", "lists adapters with the native tool" (Live)

### 14.2 Get-NetworkInterface: -Name with a wildcard

The first three letters of the first Up adapter's name, as a wildcard.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$first = (Get-NetworkInterface | Where-Object Status -eq 'Up' | Select-Object -First 1).Name
$match = @(Get-NetworkInterface -Name "$($first.Substring(0, 3))*")
'Pattern {0}*: {1} row(s), all match: {2}' -f $first.Substring(0, 3), $match.Count, (@($match | Where-Object { $_.Name -notlike "$($first.Substring(0, 3))*" }).Count -eq 0)
```

Expect: A line like `Pattern Vir*: 1 row(s), all match: True` (the first Up adapter's first three letters); the last word is always `True`.

Pester: none

### 14.3 Get-NetworkInterface: -Tool DotNet

The .NET floor lists every NetworkInterface, including ones Get-NetIPConfiguration hides.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$rows = @(Get-NetworkInterface -Tool DotNet)
$rows | Where-Object Status -eq 'Up' | Select-Object -First 3 | Format-Table Name, Status, Ip, PrefixLength
'Rows {0}, Source {1}' -f $rows.Count, (($rows.Source | Select-Object -Unique) -join ' + ')
```

Expect: Up to three Up adapters, among them `Loopback Pseudo-Interface 1 Up {::1, 127.0.0.1} {128, 8}`; then a line like `Rows 76, Source [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()` (more rows than 14.1). On Linux the Source adds `; Get-Content /sys/class/net/*/ifindex`, where InterfaceKey comes from.

Pester: "lists adapters on the .NET floor"

## 15 Get-NetworkNeighbor

### 15.1 Get-NetworkNeighbor: default (Auto)

The neighbour (ARP and NDP) table from Get-NetNeighbor.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$rows = @(Get-NetworkNeighbor)
$rows | Select-Object -First 3 | Format-Table Ip, MacAddress, Vendor, State, Interface
'Rows {0}, Source {1}' -f $rows.Count, (($rows.Source | Select-Object -Unique) -join ' + ')
```

Expect: Up to three rows with an Ip, a MacAddress, a State such as `Permanent` or `Reachable` and an Interface; then a line like `Rows 50, Source Get-NetNeighbor; [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()` (the second command is the lookup that gives each row its InterfaceKey).

Pester: "maps Get-NetNeighbor objects; an all-zero MAC is no MAC", "looks up each Get-NetNeighbor InterfaceIndex for InterfaceKey", "returns rows with Vendor, State, Interface, InterfaceKey and the command lines", "lists the live neighbour table" (Live)

### 15.2 Get-NetworkNeighbor: -IncludeUnresolved

Entries with no MAC (Unreachable, Incomplete) are left out unless asked for.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
'without {0}, with -IncludeUnresolved {1}' -f @(Get-NetworkNeighbor).Count, @(Get-NetworkNeighbor -IncludeUnresolved).Count
```

Expect: A line like `without 44, with -IncludeUnresolved 71`; the second number is never smaller.

Pester: none

### 15.3 Get-NetworkNeighbor: -Tool DotNet on Windows

Windows has no .NET floor for the neighbour table, and the error says so.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
try { Get-NetworkNeighbor -Tool DotNet } catch { $_.Exception.Message }
```

Expect: `Get-NetworkNeighbor has no .NET floor here: .NET has no API that reads the neighbour table on Windows. Install Get-NetNeighbor or arp and run Get-NetworkNeighbor -Tool Native.`

Pester: "has no .NET floor on Windows"

## 16 Get-NetworkRoute

### 16.1 Get-NetworkRoute: -AddressFamily IPv4

The IPv4 route table, with the default route.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$rows = @(Get-NetworkRoute -AddressFamily IPv4)
$rows | Where-Object PrefixLength -eq 0 | Format-Table Destination, PrefixLength, NextHop, Interface, Metric
'Rows {0}, all IPv4 {1}, Source {2}' -f $rows.Count, (@($rows | Where-Object { $_.Destination -match ':' }).Count -eq 0), (($rows.Source | Select-Object -Unique) -join ' + ')
```

Expect: One row `0.0.0.0 0 <your gateway> <your adapter> <metric>` (for example `0.0.0.0 0 192.168.0.1 Wi-Fi 0`); then a line like `Rows 30, all IPv4 True, Source Get-NetRoute; [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()` (the second command is the lookup that gives each row its InterfaceKey).

Pester: "asks only for IPv4 with -AddressFamily IPv4", "maps Get-NetRoute objects", "looks up each Get-NetRoute InterfaceIndex for InterfaceKey", "reads the live route table" (Live)

### 16.2 Get-NetworkRoute: -Tool DotNet

Routes derived from interface addresses and gateways; there is no route table on the .NET floor.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$rows = @(Get-NetworkRoute -Tool DotNet -AddressFamily IPv4)
$rows | Select-Object -First 3 | Format-Table Destination, PrefixLength, NextHop, Interface
($rows.Source | Select-Object -Unique) -join "`n"
```

Expect: On-link rows for each Up adapter's prefix (for example `192.168.0.0 24` with an empty NextHop) and a `0.0.0.0 0 <gateway>` row; then `[System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | ForEach-Object { $_.GetIPProperties() }  # .NET floor: routes derived from addresses and gateways, no route table` (unchanged on Windows, where the same call gives InterfaceKey; on Linux `; Get-Content /sys/class/net/*/ifindex` follows).

Pester: "derives on-link routes from interface addresses on the .NET floor"

## 17 Invoke-NetworkScan

### 17.1 Invoke-NetworkScan: -Target -Port -Timeout

A loopback listener and a closed port. Without nmap on PATH, Auto takes the TcpClient path; with nmap, Source is the nmap command line instead.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$rows = Invoke-NetworkScan 127.0.0.1 -Port $port, 1 -Timeout 500
$listener.Stop()
$rows | Format-Table Target, Port, Open
($rows.Source | Select-Object -Unique) -join "`n"
```

Expect: Two rows: `127.0.0.1 <port> True` and `127.0.0.1 1 False`; then two Source lines `[System.Net.Sockets.TcpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork).ConnectAsync('127.0.0.1', <port>).Wait(500)  # 64 at a time; nmap not used` and the same for port 1.

Pester: "connects to every target and port with TcpClient", "runs nmap with -oX and nothing beyond -n -Pn -p, and returns Test-NetworkPort rows"

### 17.2 Invoke-NetworkScan: a CIDR target, -Tool DotNet

A /30 target expands to its two usable addresses.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$rows = @(Invoke-NetworkScan 127.0.0.0/30 -Port 1 -Tool DotNet -Timeout 300)
$rows | Format-Table Target, Ip, Port, Open
```

Expect: Two rows: `127.0.0.1 127.0.0.1 1 False` and `127.0.0.2 127.0.0.2 1 False`.

Pester: "expands a CIDR target to its usable addresses"

### 17.3 Invoke-NetworkScan: a target too large to expand

Without nmap, more than 4096 addresses is refused before any connect.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
try { Invoke-NetworkScan 10.0.0.0/19 -Port 80 -Tool DotNet } catch { $_.Exception.Message }
```

Expect: `10.0.0.0/19 has 8190 addresses; without nmap Invoke-NetworkScan expands at most 4096. Install nmap or split the prefix (New-SubnetPlan 10.0.0.0/19 -PrefixLength 20).`

Pester: "refuses to expand more than 4096 addresses"

## 18 Resolve-NetworkName

### 18.1 Resolve-NetworkName: -Name, A and PTR

localhost, a forward lookup and a reverse lookup with the native resolver (Resolve-DnsName on Windows). Needs DNS.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Resolve-NetworkName localhost | Format-Table Name, Type, Data
(Resolve-NetworkName one.one.one.one -Type A).Data -join ', '
(Resolve-NetworkName 1.1.1.1).Data
(Resolve-NetworkName one.one.one.one -Type A)[0].Source
```

Expect: One row `localhost A 127.0.0.1`; then `1.0.0.1, 1.1.1.1`; then `one.one.one.one`; then `Resolve-DnsName -Name one.one.one.one -Type A -DnsOnly`.

Pester: "resolves localhost", "maps Resolve-DnsName objects, answers only by default", "asks for PTR with -x when given an address", "resolves with the native tool" (Live)

### 18.2 Resolve-NetworkName: -Type MX -Server

A record type the .NET floor cannot ask for, sent to a named server. Needs DNS.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Resolve-NetworkName example.com -Type MX -Server 1.1.1.1 | Format-Table Name, Type, Data
(Resolve-NetworkName example.com -Type MX -Server 1.1.1.1)[0].Source
```

Expect: One row `example.com MX 0 .` (example.com publishes a null MX); then `Resolve-DnsName -Name example.com -Type MX -DnsOnly -Server 1.1.1.1`.

Pester: "passes -Type and -Server to dig and keeps the command line"

### 18.3 Resolve-NetworkName: -Tool DotNet refusals

The .NET floor asks only the system resolver for A, AAAA and PTR, and says what to install otherwise.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
try { Resolve-NetworkName example.com -Type MX -Tool DotNet } catch { $_.Exception.Message }
try { Resolve-NetworkName example.com -Server 1.1.1.1 -Tool DotNet } catch { $_.Exception.Message }
```

Expect: `Resolve-NetworkName -Type MX is not available with DotNet. Install dig (dnsutils or bind-utils) on Linux, or use Resolve-DnsName on Windows, then run with -Tool Native.` then `Resolve-NetworkName -Server needs a native resolver (Resolve-DnsName); the .NET floor only asks the system resolver. Install one and use -Tool Native.`

Pester: "refuses record types it cannot ask for", "refuses -Server"

## 19 Test-NetworkPath

### 19.1 Test-NetworkPath: -Target -Count (Auto)

Loopback with the default tool, which is the .NET Ping on Windows.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Test-NetworkPath 127.0.0.1 -Count 2 | Format-List Target, Reachable, Sent, Received, LossPercent, AverageMs, Source
```

Expect: Target `127.0.0.1`, Reachable `True`, Sent `2`, Received `2`, LossPercent `0`, AverageMs `0`, Source `[System.Net.NetworkInformation.Ping]::new() | ForEach-Object { foreach ($i in 1..2) { $_.Send('127.0.0.1', 1000) } }`.

Pester: "on Windows, Auto takes the .NET path even with ping.exe installed (loopback, no tool runs)", "reaches loopback with the .NET floor"

### 19.2 Test-NetworkPath: -Timeout -Tool Native

The same with ping.exe.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Test-NetworkPath 127.0.0.1 -Count 2 -Timeout 500 -Tool Native | Format-List Target, Reachable, Sent, Received, LossPercent, AverageMs, Source
```

Expect: The same values, with Source `ping -n 2 -w 500 127.0.0.1`.

Pester: "reads Windows ping.exe replies", "returns one row with the exact command line as Source", "reaches 1.1.1.1 with the native ping" (Live)

## 20 Test-NetworkPort

### 20.1 Test-NetworkPort: several ports, closed

One row per port, each with its IANA service name.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Test-NetworkPort 127.0.0.1 -Port 1, 2 -Timeout 500 | Format-Table Target, Port, Protocol, Open, Service
```

Expect: Two rows: `127.0.0.1 1 Tcp False tcpmux` and `127.0.0.1 2 Tcp False` with an empty Service.

Pester: "returns one row per port with the IANA service and the nc command line", "finds the listening port open with a latency and the closed one closed"

### 20.2 Test-NetworkPort: -Protocol Udp

A UDP datagram to loopback port 53; silence or a reset is not reported open.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Test-NetworkPort 127.0.0.1 -Port 53 -Protocol Udp -Timeout 500 | Format-List Port, Protocol, Open, Service, Source
```

Expect: Port `53`, Protocol `Udp`, Open `False`, Service `domain`, Source starting `[System.Net.Sockets.UdpClient]::new('127.0.0.1', 53) | ForEach-Object { $_.Client.ReceiveTimeout = 500;`.

Pester: "does not report a closed UDP port open"

## 21 Trace-NetworkPath

### 21.1 Trace-NetworkPath: -NativeTool tracert -MaxHops

Naming the native tool runs it even though Auto on Windows is the .NET path.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Trace-NetworkPath 127.0.0.1 -NativeTool tracert -MaxHops 3 | Format-List Tool, Hop, Ip, RttMs, Responded, Source
```

Expect: One hop: Tool `tracert`, Hop `1`, Ip `127.0.0.1`, RttMs `{0, 0, 0}`, Responded `True`, Source `tracert -d -h 3 -w 1000 127.0.0.1`.

Pester: "still runs tracert by name with -NativeTool", "runs tracert -d on Windows"

### 21.2 Trace-NetworkPath: -NativeTool pathping -Queries

pathping reports only an average and a loss per hop. Takes about ten seconds.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Trace-NetworkPath 127.0.0.1 -NativeTool pathping -MaxHops 2 -Queries 3 | Format-List Tool, Hop, Ip, RttMs, AvgMs, LossPercent, Source
```

Expect: One hop: Tool `pathping`, Hop `1`, Ip `127.0.0.1`, RttMs empty `{}`, AvgMs `0`, LossPercent `0`, Source `pathping -n -h 2 -w 1000 -q 3 127.0.0.1`.

Pester: "reads Windows pathping statistics, skipping hop 0"

## 22 ConvertTo-NetworkGraph

### 22.1 ConvertTo-NetworkGraph: -InputObject from host, interfaces and routes

This host's own view as a graph, rooted at the host.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$graph = @(Get-NetworkHost; Get-NetworkInterface; Get-NetworkRoute -AddressFamily IPv4) | ConvertTo-NetworkGraph
$graph | Format-List Root, NodeCount, EdgeCount, FindingCount
$graph.Nodes | Group-Object Kind -NoElement | Sort-Object Name | Format-Table Name, Count
$graph.Edges | Group-Object Kind -NoElement | Sort-Object Name | Format-Table Name, Count
```

Expect: Root is this computer's name in lower case, with NodeCount, EdgeCount and FindingCount (for example 67, 66, 0); node kinds Host (1), Interface (for example 10: the adapters, plus the loopback pseudo-interface the routes name), RemoteHost (the gateway, 1), Route, Subnet; edge kinds Contains and RoutesTo. Each route merges into the Interface node of its adapter by InterfaceKey, so there are no extra Interface nodes.

Pester: "roots the graph at the host from Get-NetworkHost", "links host, interface, subnet and route with Contains and RoutesTo", "uses the documented Id per kind", "Route Ids end in the InterfaceKey of the interface that contains them"

### 22.2 ConvertTo-NetworkGraph: subnets alone

A host-less graph from Get-Subnet rows, with an overlap and a subnet below its cloud's minimum.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$graph = @(Get-Subnet 10.0.0.0/24 -Cloud Azure; Get-Subnet 10.0.0.128/25 -Cloud Azure; Get-Subnet 10.0.1.0/30 -Cloud AWS 3>$null) | ConvertTo-NetworkGraph
'Root [{0}]' -f $graph.Root
$graph.Findings | Format-Table Finding, NodeId, RelatedId
```

Expect: `Root []` (no host), then two findings: `BelowCloudMinimum 10.0.1.0/30@AWS` and `SubnetOverlap 10.0.0.0/24@Azure 10.0.0.128/25@Azure`.

Pester: "builds a host-less graph from subnets alone", "reports <Finding> on <NodeId>", "names the related subnet of an overlap"

## 23 Get-NetworkGraphData

### 23.1 Get-NetworkGraphData: default

Every data kind with where it was read from and when it was pulled.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-NetworkGraphData | Format-Table Kind, Location, Pulled, Entries
```

Expect: Six rows in this order: CloudReservations, SpecialUse, CloudRanges, Oui, Ports, IpSources, each with Location `Bundled` or `User` (User once Update-NetworkGraphData has run), a Pulled date and an Entries count (for example CloudReservations 4, IpSources 3).

Pester: "lists every kind with its location, pulled date and sources"

### 23.2 Get-NetworkGraphData: -Kind

The parsed document for one kind: Azure's reserved addresses, each citing its page.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$doc = Get-NetworkGraphData -Kind CloudReservations
$doc.Data.clouds.Azure.reserved | ForEach-Object { [pscustomobject]$_ } | Format-Table from, offset, role
```

Expect: Five rows: `first 0 Network address`, `first 1 Default gateway`, `first 2 Azure DNS mapping`, `first 3 Azure DNS mapping`, `last 0 Broadcast address`.

Pester: "returns the parsed document with -Kind"

### 23.3 Get-NetworkGraphData: -Sources

One row per source URL behind the data.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Get-NetworkGraphData -Sources | Group-Object Kind -NoElement | Format-Table Name, Count
(Get-NetworkGraphData -Sources | Where-Object Kind -eq 'SpecialUse' | Select-Object -First 1).Url
```

Expect: Source counts per kind (CloudRanges 8, CloudReservations 6, IpSources 6, Oui 1, Ports 1, SpecialUse 5 as of 2026-10-07), then `https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry-1.csv`.

Pester: "returns source rows with -Sources"

## 24 Update-NetworkGraphData

### 24.1 Update-NetworkGraphData: -Kind -Path -PassThru

One kind harvested into a throwaway folder instead of the user cache. Needs network access (iana.org).

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$out = Join-Path $env:TEMP 'networkgraph-check-24-1'
$rows = Update-NetworkGraphData -Kind SpecialUse -Path $out -PassThru
$rows | Format-List Kind, File, Location, Entries
(Get-ChildItem $out).Name
Remove-Item $out -Recurse -Force
```

Expect: Kind `SpecialUse`, File `special-use.json`, Location `Path`, Entries `53` (as of 2026-10-07); then `special-use.json`, the only file written.

Pester: "harvests into the folder given and never into src", "harvests the real sources" (Live)

### 24.2 Update-NetworkGraphData: -WhatIf

Shows where a harvest would write without downloading anything.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
Update-NetworkGraphData -Kind CloudRanges -WhatIf
```

Expect: `What if: Performing the operation "Harvest CloudRanges" on target "<LOCALAPPDATA>\NetworkGraph\data\cloud-ranges.json.gz".`

Pester: "writes the user cache by default, which then wins over the bundled copy"

## 25 Graph contract (0.2.0)

### 25.1 ConvertTo-NetworkGraph: an edge with Source

Every edge carries the Source of the row that asserted it; the default route's RoutesTo edge has the route row's Source.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$graph = @(Get-NetworkInterface; Get-NetworkRoute -AddressFamily IPv4) | ConvertTo-NetworkGraph -HostName testhost
$graph.Edges | Where-Object Kind -eq RoutesTo | Format-List From, To, Kind, Source
'Edges {0}, without Source {1}' -f $graph.EdgeCount, @($graph.Edges | Where-Object { -not $_.Source }).Count
```

Expect: One edge with From `testhost/route/0.0.0.0/0/<gateway>/{<GUID>}` (for example `testhost/route/0.0.0.0/0/192.168.0.1/{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}`), To the gateway, Kind `RoutesTo`, Source `Get-NetRoute; [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()`; then a line like `Edges 43, without Source 0` (the second number is always 0).

Pester: "every edge has a non-empty Source", "an edge takes the Source of the row that asserted it: <Name>", "property order: an Interface node is Id, Kind, Name, InterfaceName, InterfaceKey, ..., Source; an edge is From, To, Kind, Source"

### 25.2 ConvertTo-NetworkGraph: an Interface Id with its InterfaceKey

The Interface Id is built on InterfaceKey (the interface GUID on Windows, the ifindex on Linux), not the renameable alias, and the default route's Id ends in the same key.

```powershell
Set-Location 'C:\__Code\NetworkGraph'
Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
$graph = @(Get-NetworkInterface; Get-NetworkRoute -AddressFamily IPv4) | ConvertTo-NetworkGraph -HostName testhost
$default = $graph.Nodes | Where-Object { $_.Kind -eq 'Route' -and $_.PrefixLength -eq 0 } | Select-Object -First 1
$interface = $graph.Nodes | Where-Object { $_.Kind -eq 'Interface' -and $_.InterfaceKey -eq $default.InterfaceKey }
$interface | Format-List Id, Name, InterfaceName, InterfaceKey
'Route {0}' -f $default.Id
'Id is host/if/key: {0}; route ends in the same key: {1}' -f ($interface.Id -eq "testhost/if/$($interface.InterfaceKey)"), $default.Id.EndsWith("/$($interface.InterfaceKey)")
```

Expect: Id `testhost/if/{<GUID>}`, Name and InterfaceName your adapter's alias (for example `Wi-Fi`), InterfaceKey the same `{<GUID>}`; then `Route testhost/route/0.0.0.0/0/<gateway>/{<GUID>}` and `Id is host/if/key: True; route ends in the same key: True`.

Pester: "Windows Interface Ids use the GUID, not the alias", "an interface whose alias was renamed keeps its Id (same key, different alias)", "Route Ids end in the InterfaceKey of the interface that contains them", "keys the Interface node on InterfaceKey and keeps the alias as Name and InterfaceName"
