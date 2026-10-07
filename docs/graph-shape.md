# Graph shape

The contract for `ConvertTo-NetworkGraph` output. Pester ("node property names equal the contract in docs/graph-shape.md", "edge property names equal the contract in docs/graph-shape.md") parses the two tables below and fails if a node or edge carries different property names, or the same names in a different order. `$script:NetworkGraphNodeContract` in `NetworkGraph.psm1` holds the same lists; `Add-NetworkGraphNode` refuses a property not in it.

## Where it came from

The names match what `ConvertTo-TerraformResourceGraph` in TerraformGraph (`C:\__Code\TerraformGraph\src\TerraformGraph\TerraformGraph.psm1`, 0.14.0) emits, so one renderer can draw both graphs:

| TerraformGraph (ResourceGraph) | NetworkGraph (Graph) | Match |
|---|---|---|
| graph `Root` | graph `Root` (the Host node Id, or `$null` when no host was involved) | same name |
| graph `Nodes` | graph `Nodes` | same name |
| graph `Edges` | graph `Edges` | same name |
| script properties `NodeCount`, `EdgeCount` | script properties `NodeCount`, `EdgeCount` | same names |
| node `Id` (first), `Kind` (second) | node `Id` (first), `Kind` (second) | same names, same positions |
| node `Name` | node `Name` | same name (ResourceNode and SchemaNode both carry it) |
| edge `From`, `To`, `Kind` (ResourceEdge, and SchemaEdge) | edge `From`, `To`, `Kind` | identical, nothing else on the edge |
| `Findings`: script property, an **int** (nodes with UnknownAttributes, UnknownBlocks or MissingRequired) | `Findings`: an **array** of NetworkGraph.Finding rows, plus script property `FindingCount` | same name, different type (see below) |
| `Skipped`, `Providers`, `MatchedCount`, `UnmatchedCount` | none | Terraform-only |
| node `File`, `Line`, `Block` (where the node came from) | node `Source` (the tool and command line, or data file) | different name for the same role |

Edge `Kind` values are PascalCase, as in TerraformGraph (`Contains`, `RoutesTo`, `HopsTo`, `ConnectsTo`, `OwnedBy`, `ResolvesTo`, `BelongsTo`). 0.1.0 used lower-case hyphenated kinds (`contains`, `routes-to`, ...); they were renamed on 2026-10-07 and are now compared case-sensitively, so `contains` is no longer a kind.

Differences a shared renderer has to know, as of 2026-10-07. Both are TerraformGraph's to close: TerraformGraph will adopt the NetworkGraph shape, and NetworkGraph keeps both as they are.

- `Findings` is a count in TerraformGraph and a list here. Code that reads `$graph.Findings` as a number should read `FindingCount` on a NetworkGraph graph. TerraformGraph will make `Findings` the list of rows and add `FindingCount`.
- Where a node came from is `File`, `Line`, `Block` in TerraformGraph and `Source` here. TerraformGraph will add `Source`.

## Node properties

Every node: `Id`, `Kind`, `Name`, the kind's own properties, then `Source`. `Name` is a display label and may repeat; `Id` is unique within one graph.

| Kind | Id scheme | Properties |
|---|---|---|
| Host | `<hostname>` lower case | Id, Kind, Name, HostName, Os, Source |
| Interface | `<host>/if/<interface name>` | Id, Kind, Name, InterfaceName, Ip, PrefixLength, MacAddress, Vendor, Status, Source |
| Subnet | `<cidr>@<cloud>`, for example `10.0.1.0/24@Azure`; `@None` for an interface's subnet | Id, Kind, Name, Cidr, Cloud, PrefixLength, Usable, BelowCloudMinimum, Source |
| Route | `<host>/route/<cidr>/<next hop or on-link>/<interface or ->` | Id, Kind, Name, Destination, PrefixLength, NextHop, InterfaceName, Metric, Source |
| Hop | `hop/<target>/<tool>/<hop number>`; tool is tracert, pathping, mtr, traceroute or DotNet | Id, Kind, Name, Target, Hop, Ip, RttMs, AvgMs, LossPercent, Responded, Source |
| Connection | `<host>/conn/<tcp or udp>/<local ip>:<port>/<remote ip>:<port>/<pid>`, IPv6 in brackets, remote `*` for a listener, `/<pid>` only when the process is known | Id, Kind, Name, Protocol, LocalIp, LocalPort, RemoteIp, RemotePort, State, ProcessId, Source |
| Process | `<host>:<pid>` | Id, Kind, Name, ProcessId, ProcessName, Source |
| RemoteHost | `<ip>`; a DNS name with no address of its own is `dns:<name>` | Id, Kind, Name, Ip, RemoteHost, MacAddress, Vendor, Cloud, Service, Asn, Owner, OpenPorts, Source |
| Cloud | `cloud/<cloud>` (Azure, AWS, GCP, Google) | Id, Kind, Name, Cloud, Source |
| Asn | `AS<number>` | Id, Kind, Name, Asn, Owner, Source |

Hop values: `RttMs` is per-probe samples only; `AvgMs` is their mean, or the tool's own average where it reports only that (mtr, pathping: `RttMs` empty). `Responded` is `$false` for a hop that answered no probe. Such a hop has `LossPercent` `$null` when a later hop answered (the router does not send ICMP Time Exceeded; the path delivered), keeps a real `LossPercent` when some probes answered, and keeps 100 when no later hop answered either.

### Changed in 0.1.1

- Hop: new properties `AvgMs` (after RttMs) and `Responded` (after LossPercent). `RttMs` now always means per-probe samples; mtr's and pathping's averages moved from `RttMs` to `AvgMs`. `LossPercent` is `$null` for a silent hop followed by one that answered (was 100).
- Hop Id: `hop/<target>/<n>` became `hop/<target>/<tool>/<n>`, so a native and a .NET trace of the same target are two chains instead of one merged chain.
- Connection Id: `/<pid>` is appended when the process is known, so sockets sharing an endpoint (SO_REUSEADDR) are separate nodes, each with its own OwnedBy edge.

Naming rule: no node property is called `Address`, `Count`, `Length` or any other member of `System.Array`, because member access on an array of nodes (`$graph.Nodes.Count`) would hit the array's member instead. Hence `Ip`, `InterfaceName`, `Hop`, `OpenPorts`.

Interface subnets skip loopback and link-local prefixes and host prefixes (/32, /128), which would merge unrelated links into one node.

## Edge properties

| Type | Properties |
|---|---|
| Edge | From, To, Kind |

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
