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

Differences a shared renderer has to know:

- Edge `Kind` values. TerraformGraph uses PascalCase (`InstanceOf`, `Contains`, `Reference`); NetworkGraph uses the lower-case hyphenated kinds the module spec names (`contains`, `routes-to`, ...). Property names are identical; values differ in case. Compare case-insensitively, or map `contains` to `Contains`.
- `Findings` is a count in TerraformGraph and a list here. Code that reads `$graph.Findings` as a number should read `FindingCount` on a NetworkGraph graph.

## Node properties

Every node: `Id`, `Kind`, `Name`, the kind's own properties, then `Source`. `Name` is a display label and may repeat; `Id` is unique within one graph.

| Kind | Id scheme | Properties |
|---|---|---|
| Host | `<hostname>` lower case | Id, Kind, Name, HostName, Os, Source |
| Interface | `<host>/if/<interface name>` | Id, Kind, Name, InterfaceName, Ip, PrefixLength, MacAddress, Vendor, Status, Source |
| Subnet | `<cidr>@<cloud>`, for example `10.0.1.0/24@Azure`; `@None` for an interface's subnet | Id, Kind, Name, Cidr, Cloud, PrefixLength, Usable, BelowCloudMinimum, Source |
| Route | `<host>/route/<cidr>/<next hop or on-link>/<interface or ->` | Id, Kind, Name, Destination, PrefixLength, NextHop, InterfaceName, Metric, Source |
| Hop | `hop/<target>/<hop number>` | Id, Kind, Name, Target, Hop, Ip, RttMs, LossPercent, Source |
| Connection | `<host>/conn/<tcp or udp>/<local ip>:<port>/<remote ip>:<port>`, IPv6 in brackets, remote `*` for a listener | Id, Kind, Name, Protocol, LocalIp, LocalPort, RemoteIp, RemotePort, State, ProcessId, Source |
| Process | `<host>:<pid>` | Id, Kind, Name, ProcessId, ProcessName, Source |
| RemoteHost | `<ip>`; a DNS name with no address of its own is `dns:<name>` | Id, Kind, Name, Ip, RemoteHost, MacAddress, Vendor, Cloud, Service, Asn, Owner, OpenPorts, Source |
| Cloud | `cloud/<cloud>` (Azure, AWS, GCP, Google) | Id, Kind, Name, Cloud, Source |
| Asn | `AS<number>` | Id, Kind, Name, Asn, Owner, Source |

Naming rule: no node property is called `Address`, `Count`, `Length` or any other member of `System.Array`, because member access on an array of nodes (`$graph.Nodes.Count`) would hit the array's member instead. Hence `Ip`, `InterfaceName`, `Hop`, `OpenPorts`.

Interface subnets skip loopback and link-local prefixes and host prefixes (/32, /128), which would merge unrelated links into one node.

## Edge properties

| Type | Properties |
|---|---|
| Edge | From, To, Kind |

Edge kinds, From to To:

| Kind | From | To |
|---|---|---|
| contains | Host | Interface, Process, Connection, Route (when the route names no interface) |
| contains | Interface | Route |
| contains | Subnet | Interface (an address of the interface is in the subnet), Subnet (a New-SubnetPlan child) |
| routes-to | Route | RemoteHost (its next hop) |
| routes-to | Host | RemoteHost (its external address, Get-ExternalIpAddress) |
| hops-to | Host | first Hop of a trace |
| hops-to | Hop | next Hop |
| connects-to | Connection | RemoteHost |
| connects-to | Interface | RemoteHost (a neighbour seen on that interface) |
| owned-by | Connection | Process |
| resolves-to | RemoteHost `dns:<name>` | RemoteHost `<ip>` (A, AAAA) or `dns:<name>` (CNAME) |
| resolves-to | RemoteHost `<ip>` | RemoteHost `dns:<name>` (PTR) |
| belongs-to | RemoteHost | Cloud, Asn |

## Findings

`NetworkGraph.Finding`: `Finding`, `NodeId`, `RelatedId`, `Detail`.

| Finding | NodeId | RelatedId | When |
|---|---|---|---|
| SubnetOverlap | Subnet | the other Subnet | two subnets share addresses and neither is the other's New-SubnetPlan ancestor |
| BelowCloudMinimum | Subnet | | smaller than Azure or GCP /29, AWS /28 |
| NonCloudPublicConnection | Connection | RemoteHost | the remote address is public (no special-use row) and in no harvested cloud range |
| WildcardListener | Connection | | TCP Listen on 0.0.0.0 or :: |
| RouteWithoutInterface | Route | | the route row names no interface |
