# Graph shape

The contract for `ConvertTo-NetworkGraph` output. Pester ("node property names equal the contract in docs/graph-shape.md", "edge property names equal the contract in docs/graph-shape.md") parses the two tables below and fails if a node or edge carries different property names, or the same names in a different order. `$script:NetworkGraphNodeContract` in `Graph.Emitter.Network.psm1` holds the same lists; `Add-NetworkGraphNode` refuses a property not in it.

## Where it came from

The names match what `ConvertTo-TerraformResourceGraph` in TerraformGraph (`C:\__Code\TerraformGraph\src\TerraformGraph\TerraformGraph.psm1`, 0.14.0) emits, so one renderer can draw both graphs:

| TerraformGraph (ResourceGraph) | Graph.Emitter.Network (Graph) | Match |
|---|---|---|
| graph `Root` | graph `Root` (the Host node Id, or `$null` when no host was involved) | same name |
| graph `Nodes` | graph `Nodes` | same name |
| graph `Edges` | graph `Edges` | same name |
| script properties `NodeCount`, `EdgeCount` | script properties `NodeCount`, `EdgeCount` | same names |
| node `Id` (first), `Kind` (second) | node `Id` (first), `Kind` (second) | same names, same positions |
| node `Name` | node `Name` | same name (ResourceNode and SchemaNode both carry it) |
| edge `From`, `To`, `Kind` (ResourceEdge, and SchemaEdge) | edge `From`, `To`, `Kind`, then `Source` (from 0.2.0) | same names and positions; `Source` is extra |
| `Findings`: script property, an **int** (nodes with UnknownAttributes, UnknownBlocks or MissingRequired) | `Findings`: an **array** of NetworkGraph.Finding rows, plus script property `FindingCount` | same name, different type (see below) |
| `Skipped`, `Providers`, `MatchedCount`, `UnmatchedCount` | none | Terraform-only |
| node `File`, `Line`, `Block` (where the node came from) | node `Source` (the tool and command line, or data file) | different name for the same role |

Edge `Kind` values are PascalCase, as in TerraformGraph (`Contains`, `RoutesTo`, `HopsTo`, `ConnectsTo`, `OwnedBy`, `ResolvesTo`, `BelongsTo`). 0.1.0 used lower-case hyphenated kinds (`contains`, `routes-to`, ...); they were renamed on 2026-10-07 and are now compared case-sensitively, so `contains` is no longer a kind.

Differences a shared renderer has to know, as of 2026-10-07. Both are TerraformGraph's to close: TerraformGraph will adopt the Graph.Emitter.Network shape, and Graph.Emitter.Network keeps both as they are.

- `Findings` is a count in TerraformGraph and a list here. Code that reads `$graph.Findings` as a number should read `FindingCount` on a Graph.Emitter.Network graph. TerraformGraph will make `Findings` the list of rows and add `FindingCount`.
- Where a node came from is `File`, `Line`, `Block` in TerraformGraph and `Source` here. TerraformGraph will add `Source`.
- Edges carry a fourth property, `Source`, here (from 0.2.0) and none in TerraformGraph. A renderer that reads `From`, `To`, `Kind` by name is unaffected.

## Node properties

Every node: `Id`, `Kind`, `Name`, the kind's own properties, then `Source`. `Name` is a display label and may repeat; `Id` is unique within one graph.

| Kind | Id scheme | Properties |
|---|---|---|
| Host | `<hostname>` lower case | Id, Kind, Name, HostName, Os, Source |
| Interface | `<host>/if/<InterfaceKey>`: the interface GUID on Windows, the ifindex on Linux (see Interface and Route Ids) | Id, Kind, Name, InterfaceName, InterfaceKey, Ip, PrefixLength, MacAddress, Vendor, Status, Source |
| Subnet | `<cidr>@<cloud>`, for example `10.0.1.0/24@Azure`; `@None` for an interface's subnet | Id, Kind, Name, Cidr, Cloud, PrefixLength, Usable, BelowCloudMinimum, Source |
| Route | `<host>/route/<cidr>/<next hop or on-link>/<InterfaceKey, else interface name, else ->` | Id, Kind, Name, Destination, PrefixLength, NextHop, InterfaceName, InterfaceKey, Metric, Source |
| Hop | `hop/<target>/<tool>/<hop number>`; tool is tracert, pathping, mtr, traceroute or DotNet | Id, Kind, Name, Target, Hop, Ip, RttMs, AvgMs, LossPercent, Responded, Source |
| Connection | `<host>/conn/<tcp or udp>/<local ip>:<port>/<remote ip>:<port>/<pid>`, IPv6 in brackets, remote `*` for a listener, `/<pid>` only when the process is known | Id, Kind, Name, Protocol, LocalIp, LocalPort, RemoteIp, RemotePort, State, ProcessId, Source |
| Process | `<host>:<pid>`; capture-scoped (see below) | Id, Kind, Name, ProcessId, ProcessName, Source |
| RemoteHost | `<ip>`; a DNS name with no address of its own is `dns:<name>` | Id, Kind, Name, Ip, RemoteHost, MacAddress, Vendor, Cloud, Service, Asn, Owner, OpenPorts, Source |
| Cloud | `cloud/<cloud>` (Azure, AWS, GCP, Google) | Id, Kind, Name, Cloud, Source |
| Asn | `AS<number>` | Id, Kind, Name, Asn, Owner, Source |

Hop values: `RttMs` is per-probe samples only; `AvgMs` is their mean, or the tool's own average where it reports only that (mtr, pathping: `RttMs` empty). `Responded` is `$false` for a hop that answered no probe. Such a hop has `LossPercent` `$null` when a later hop answered (the router does not send ICMP Time Exceeded; the path delivered), keeps a real `LossPercent` when some probes answered, and keeps 100 when no later hop answered either.

### Interface and Route Ids

An interface's alias (Windows `InterfaceAlias`, the Linux device name) can be renamed, so an Id built on it forks the node: the same adapter before and after `Rename-NetAdapter` would be two Interface nodes. From 0.2.0 the Id is built on `InterfaceKey`, which the observe rows carry and the node keeps so the derivation can be read back:

- Windows: the interface GUID, `{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}`. `Get-NetworkInterface` reads it from `Get-NetIPConfiguration` (`NetAdapter.InterfaceGuid`). Get-NetRoute, Get-NetNeighbor and arp name an interface by index, so `Get-NetworkRoute` and `Get-NetworkNeighbor` look the index up in `[System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()` at the same moment (its `Id` is the same GUID, and it includes the loopback pseudo-interface, which Get-NetAdapter leaves out) and name that call in Source. The GUID lasts as long as the adapter is installed.
- Linux: the ifindex, `ifindex` in `ip -j addr`. ip route, ip neigh, arp and /proc/net/arp name a device, so the lookup reads `/sys/class/net/<dev>/ifindex`. The key is **boot-scoped**: the kernel numbers interfaces as they appear, so a reboot, a module reload or a recreated virtual interface (a container's veth, a VPN tun) can give it a different index. It is still the key, because it is the one identifier every interface has: there is no GUID, the device name is the renameable alias, and loopback and tunnels have no MAC (see docs/design.md). Compare Linux graphs within one boot.
- `Name` and `InterfaceName` stay the alias, for display.
- A row with no key (a row from 0.1.x, or a tool that gave neither index nor name the lookup knew) borrows the key of an Interface row with the same name in the same input; failing that its Interface Id falls back to `<host>/if/<alias>` with `InterfaceKey` `$null`, and that node does not merge with the keyed one.

A Route Id ends in the same key, so a route's Id and the Id of the interface that `Contains` it agree: `<host>/route/<cidr>/<next hop or on-link>/<InterfaceKey>`, for example `testhost/route/0.0.0.0/0/192.168.0.1/{00000000-0000-0000-0000-000000000016}` (Windows) or `testhost/route/0.0.0.0/0/172.17.0.1/2` (Linux). Without a key it ends in the interface name, and `-` when the route names no interface (the RouteWithoutInterface finding).

Hop, Process and Host Ids are unchanged. A Process Id, `<host>:<pid>`, is capture-scoped by design: the operating system reuses process ids, so the same Id in two captures can be two different processes. It identifies a process within one graph, which is what OwnedBy needs.

### Changed in 0.2.0

- Edge: new property `Source`, after Kind (see Edge properties).
- Interface: new property `InterfaceKey` (after InterfaceName); the Id is `<host>/if/<InterfaceKey>` instead of `<host>/if/<interface name>`.
- Route: new property `InterfaceKey` (after InterfaceName); the Id ends in the InterfaceKey instead of the interface name.

### Changed in 0.1.1

- Hop: new properties `AvgMs` (after RttMs) and `Responded` (after LossPercent). `RttMs` now always means per-probe samples; mtr's and pathping's averages moved from `RttMs` to `AvgMs`. `LossPercent` is `$null` for a silent hop followed by one that answered (was 100).
- Hop Id: `hop/<target>/<n>` became `hop/<target>/<tool>/<n>`, so a native and a .NET trace of the same target are two chains instead of one merged chain.
- Connection Id: `/<pid>` is appended when the process is known, so sockets sharing an endpoint (SO_REUSEADDR) are separate nodes, each with its own OwnedBy edge.

Naming rule: no node property is called `Address`, `Count`, `Length` or any other member of `System.Array`, because member access on an array of nodes (`$graph.Nodes.Count`) would hit the array's member instead. Hence `Ip`, `InterfaceName`, `Hop`, `OpenPorts`.

Interface subnets skip loopback and link-local prefixes and host prefixes (/32, /128), which would merge unrelated links into one node.

## Edge properties

| Type | Properties |
|---|---|
| Edge | From, To, Kind, Source |

`Source` has the same meaning as on a node: the pasteable command line (or data-file citation) that produced the edge. Every edge has one. The rule for an edge between nodes that came from different rows: the edge takes the Source of the row that **asserted the relation**, which is the row whose processing created the edge.

| Edge | Source |
|---|---|
| Host Contains Interface, Subnet Contains Interface | the Interface row (it lists the address that puts the interface in the subnet); a route or neighbour row that names an interface asserts the Host Contains Interface edge when no Interface row did |
| Interface or Host Contains Route, Route RoutesTo RemoteHost | the Route row |
| Subnet Contains Subnet | the planned subnet's Source (the New-SubnetPlan citation) |
| Host Contains Connection and Process, Connection OwnedBy Process, Connection ConnectsTo RemoteHost | the Connection row |
| Interface ConnectsTo RemoteHost | the Neighbor row |
| Host RoutesTo RemoteHost | the ExternalIp row |
| HopsTo | the Hop row the edge points to |
| ResolvesTo | the DnsRecord row |
| BelongsTo | the row that carried Cloud or Asn; `Test-IPAddress <ip>` when ConvertTo-NetworkGraph classified the address itself |

When several rows assert the same edge (same From, To and Kind), the first keeps its Source. A row built by hand with no Source gives its edges `<type name> (no Source)`.

Edge kinds, From to To:

| Kind | From | To |
|---|---|---|
| Contains | Host | Interface, Process, Connection, Route (when the route names no interface) |
| Contains | Interface | Route |
| Contains | Subnet | Interface (an address of the interface is in the subnet), Subnet (a New-SubnetPlan child) |
| RoutesTo | Route | RemoteHost (its next hop) |
| RoutesTo | Host | RemoteHost (its external address, Get-ExternalIpAddress) |
| HopsTo | Host | first Hop of a trace |
| HopsTo | Hop | next Hop |
| ConnectsTo | Connection | RemoteHost |
| ConnectsTo | Interface | RemoteHost (a neighbour seen on that interface) |
| OwnedBy | Connection | Process |
| ResolvesTo | RemoteHost `dns:<name>` | RemoteHost `<ip>` (A, AAAA) or `dns:<name>` (CNAME) |
| ResolvesTo | RemoteHost `<ip>` | RemoteHost `dns:<name>` (PTR) |
| BelongsTo | RemoteHost | Cloud, Asn |

## Findings

`NetworkGraph.Finding`: `Finding`, `NodeId`, `RelatedId`, `Detail`.

| Finding | NodeId | RelatedId | When |
|---|---|---|---|
| SubnetOverlap | Subnet | the other Subnet | two subnets share addresses and neither is the other's New-SubnetPlan ancestor |
| BelowCloudMinimum | Subnet | | smaller than Azure or GCP /29, AWS /28 |
| NonCloudPublicConnection | Connection | RemoteHost | the remote address is public (no special-use row) and in no harvested cloud range |
| WildcardListener | Connection | | TCP Listen on 0.0.0.0 or :: |
| RouteWithoutInterface | Route | | the route row names no interface |
