# NetworkGraph manual check list

Module version: 0.1.0
Last updated: 2026-10-07

Every block starts a fresh process (`pwsh -NoProfile -Command { ... }`) and imports the module from `src`, so no item depends on another or on the shell it is pasted into. Objects come back across the process boundary deserialized, so lists show every property rather than the default view; the Expect lines describe what that looks like. Items are append-only: never renumber, mark a removed item "(removed in x.y.z)".

Verified for 0.1.0: every item below was run on Windows 11 (PowerShell 7.6.6) and its Expect line written from that output. Items 1.1, 1.2, 1.3 and 1.7 were also run on Linux (Ubuntu 22.04 container, PowerShell 7, with the repository path changed to the container's) with the same output; 1.4, 1.5 and 1.6 depend on the host's own connections and path and were exercised on Linux through the Live Pester tests, not by these blocks.

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

Expect: `0.1.0`, then `23`, then ConvertFrom-SubnetMask, ConvertTo-NetworkGraph, ConvertTo-SubnetMask, Get-ExternalIpAddress, Get-MacAddressVendor, Get-NetworkConnection, Get-NetworkGraphData, Get-NetworkHost, Get-NetworkInterface, Get-NetworkNeighbor, Get-NetworkRoute, Get-Subnet, Get-SubnetChildren, Get-SubnetParent, Invoke-NetworkScan, New-SubnetPlan, Resolve-NetworkName, Test-IPAddress, Test-NetworkPath, Test-NetworkPort, Test-SubnetOverlap, Trace-NetworkPath, Update-NetworkGraphData.

Pester: "is version 0.1.0 and needs PowerShell 7.4", "psd1 exports match Public/", "exports 23 functions in three groups by noun", "every Public file exports exactly its function name"

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

Expect: up to five rows with Cloud filled (Azure, AWS, GCP or Google), a Service such as `AzureCloud.eastus2` or `Google Cloud`, Asn 8075, 16509 or 15169 and a ProcessName; then a line like `Rows 399, with Cloud 35, Source Get-NetTCPConnection + Get-NetUDPEndpoint` where the Cloud count is at least 1 (counts vary by machine). With a browser or OneDrive running there are always cloud rows.

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

Expect: two hop tables with the same addresses in the same order, the first hop your gateway (for example 192.168.0.1) and the last `1.1.1.1` with LossPercent 0; a hop that drops probes shows a LossPercent above 0 or an empty Ip. Between them `tracert -d -h 3 -w 1000 1.1.1.1`, and after the second `[System.Net.NetworkInformation.Ping]::new().Send('1.1.1.1', 1000, buffer, [PingOptions]::new(ttl, $true)) for ttl 1..3 x 3`. Native RTTs are whole milliseconds; .NET RTTs have decimals except at the last hop.

Pester: "reads Windows tracert, including a timed-out hop", "runs tracert -d on Windows", "traces 1.1.1.1 with the native tool and the .NET floor" (Live)

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

Expect: Root is this computer's name in lower case, with NodeCount, EdgeCount and FindingCount (for example 524, 1047, 61). Node kinds Asn, Cloud, Connection, Host (1), Process, RemoteHost, where Connection equals the row count from 1.4 and Cloud is 1 to 4; edge kinds BelongsTo, ConnectsTo, Contains, OwnedBy; findings WildcardListener and usually NonCloudPublicConnection.

Pester: "node property names equal the contract in docs/graph-shape.md", "gives every node a unique Id", "reports WildcardListener on testhost/conn/tcp/0.0.0.0:8080/*", "graphs the live connections of this host" (Live)

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

Expect: two lists. The first: Open `True`, a LatencyMs (for example `28.6`), Source `[System.Net.Sockets.TcpClient]::new().ConnectAsync('127.0.0.1', <port>), timeout 2000`. The second: Open `True`, LatencyMs empty, Source `Test-NetConnection -ComputerName 127.0.0.1 -Port <port>`. Then `True`: the filtered address took the one-second timeout, not Test-NetConnection's twenty seconds.

Pester: "Auto uses the .NET TcpClient path even when the native tool is installed", "returns one row per port with the IANA service and the nc command line"

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
