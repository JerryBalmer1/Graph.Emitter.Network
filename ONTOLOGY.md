> **NetworkGraph is an ontology layer for AI agents over what a host can see on its network.** One Id names an address in a socket, a trace, a registry row and a cloud range, and every row says which tool produced it.

Here for the PowerShell module, install steps and examples? Read [README.md](README.md).

## The ontology was already there

If you build ontologies or agent memory, a host's network has probably never been on your list of sources. Look at what is already in place.

Every address is already classified by someone whose job it is. IANA keeps the special-purpose registries (private, CGNAT, loopback, documentation, multicast: RFC 6890 and the RFCs each row cites) and the service name and port registry. IEEE assigns the first three bytes of every MAC address to a named vendor. Azure, AWS and Google publish every prefix they own, with the service and region behind it, and their docs state which addresses in a subnet they reserve. Regional registries answer RDAP for who holds any public block. These are typed, versioned by publication date and authoritative.

And every host already keeps the instances. The socket table says which process talks to which address and port; the route table says which next hop carries a prefix; the neighbour table says which MAC answered for which address; ping, tracert, traceroute, mtr and pathping say which routers answered on the way. The OS keeps these correct every second, and the tools that print them are already installed.

Nobody built a network ontology for a single host because nobody had to: the vocabulary and the instances were both there. What was missing was the join. NetworkGraph adds one Id for an address that holds across the socket, the trace hop, the registry row and the cloud range, a `Source` on every row that names the exact command line or data file it came from, and a graph whose node and edge shape matches TerraformGraph's, so declared infrastructure and observed infrastructure can be drawn by one renderer. The rest of this page is that join.

## What this is

A PowerShell module that turns what a host can see into named, typed, joined data an agent can query instead of guess at. Five layers share one key, the address:

| Layer | Where it comes from | Example for one Azure address |
|---|---|---|
| Socket | Get-NetTCPConnection, Get-NetUDPEndpoint, `ss -tunap`, or .NET `IPGlobalProperties` | Connection node such as `testhost/conn/tcp/192.168.0.6:52311/13.85.16.224:443/1264`, `RemoteIp` `13.85.16.224` |
| Address | the socket's remote end, a trace hop, a neighbour, a DNS answer | RemoteHost node `13.85.16.224` |
| Registry | IANA special-purpose registries (`data/special-use.json`) | no row, so `Scope` `Public` |
| Cloud range | Azure Service Tags (`data/cloud-ranges.json.gz`) | Cloud `Azure`, Service `AppService`, `CloudPrefix` `13.85.16.224/32`; nodes `cloud/Azure` and `AS8075` |
| Path | tracert, traceroute, mtr, pathping, or TTL-stepped .NET `Ping` | Hop node `hop/13.85.16.224/DotNet/<n>` |

The Connection's `RemoteIp` is the RemoteHost's `Id`, which is the Hop's `Ip` and what `Test-IPAddress` classifies. No lookup tables, no fuzzy matching: a join either holds or is reported as a finding.

## Why a host's network is an unusually good ontology source

- **Typed.** An address is IPv4 or IPv6 with a prefix; a port is a number with a registered service; a MAC is six bytes whose first three name a vendor. The OS tables have fixed columns, and the better tools emit structure (`ip -j`, `mtr --json`, `nmap -oX`, cmdlet objects).
- **Published.** The classes come from registries and vendors with URLs and publication dates: IANA, IEEE, the clouds' range files and subnet docs, RDAP. Each data file in NetworkGraph names those URLs and the date it pulled them.
- **Observable by the tools already installed.** Nothing has to be deployed or granted: the socket, route and neighbour tables and a trace are readable by an ordinary user on Windows and Linux. NetworkGraph wraps those tools and ships no binary, so every row can be reproduced by pasting its `Source`.
- **Already joined in practice.** A connection to 13.85.16.224 is to exactly one address, which is in or out of each registry row and each cloud prefix. NetworkGraph only has to make the edges explicit (`ConnectsTo`, `BelongsTo`, `HopsTo`, `ResolvesTo`).

## What agents get

Named things, not guesses:

- **Stable Ids.** Host `<hostname>` (lower case); Interface `<host>/if/<name>`; Subnet `<cidr>@<cloud>`; Route `<host>/route/<cidr>/<next hop or on-link>/<interface>`; Hop `hop/<target>/<tool>/<n>`; Connection `<host>/conn/<tcp|udp>/<local ip>:<port>/<remote ip>:<port>[/<pid>]`; Process `<host>:<pid>`; RemoteHost `<ip>` or `dns:<name>`; Cloud `cloud/<cloud>`; Asn `AS<number>`. [docs/graph-shape.md](docs/graph-shape.md) is the contract, and Pester compares it with real nodes.
- **The same shape as TerraformGraph.** Graph `Root`, `Nodes`, `Edges`, `NodeCount`, `EdgeCount`; nodes `Id`, `Kind` first; edges exactly `From`, `To`, `Kind` with PascalCase kinds. Two differences remain and are TerraformGraph's to close: `Findings` is a list here and a count there, and where a node came from is `Source` here and `File`, `Line`, `Block` there.
- **Error ids, where they exist.** Refusals of an argument carry a `FullyQualifiedErrorId` of the form `<Id>,<command>` you can branch on: `NonContiguousMask`, `InvalidMask`, `PrefixLengthOutOfRange`, `PlanDoesNotFit`, `TooManySubnets`, `TooManyTargets`, `RecordTypeNeedsNativeTool`, `ServerNeedsNativeTool`, `NoExternalAddress`, `NmapFailed`. Per-item failures are non-terminating with ids: `InvalidMacAddress`, `DnsQueryFailed`, `PingFailed`, `NativeToolFailed`, `RdapFailed`, `TargetNotResolved`. Not every error has one yet: a missing .NET floor, unrecognised tool output and some prefix parsing errors are thrown exceptions whose id is their message, so match on the exception type, not the id.
- **Provenance on every row.** `Source` is the tool and exact command line (`tracert -d -h 3 -w 1000 1.1.1.1`), the .NET expression (`[System.Net.NetworkInformation.Ping]::new() | ...`), or the data file with its pulled date and URL. A .NET floor that lacks a field says so in `Source` ("no process information"). Pester parses every `Source` the module can emit.
- **Findings, not errors.** What the data shows but should not be is data: `SubnetOverlap`, `BelowCloudMinimum`, `NonCloudPublicConnection`, `WildcardListener`, `RouteWithoutInterface`, each a `NetworkGraph.Finding` with the node it is about. The graph still builds.
- **Provenance on bundled data.** Every data file has `formatVersion`, `kind`, `maxAgeDays`, `pulled` and a `sources` array of `{ url, title, pulled }`; `Get-NetworkGraphData` lists them and where each was read from, `Get-NetworkGraphData -Sources` every URL, and `Invoke-Build CheckData` fails a file older than its `maxAgeDays`, naming the command that refreshes it.
- **Promote or leave.** Harvests write the user cache; the module's shipped data changes only through `Invoke-Build UpdateData`. An agent that finds stale data reports it and refreshes it only when its task is about that data.
- **Nothing hidden on the network.** The calculate commands and `ConvertTo-NetworkGraph` never touch the network. The observe commands touch it only as their names say (a ping pings, a trace traces, `-Resolve` does reverse DNS), and only `Get-ExternalIpAddress` and `Update-NetworkGraphData` make web requests, HTTPS only (`curl --proto =https`, or a helper that refuses any other scheme).

## Terminology

| Term | In the module | What it is |
|---|---|---|
| Id | `NetworkGraph.Node.Id`, `NetworkGraph.Edge.From`, `NetworkGraph.Finding.NodeId` | The canonical string for one thing in a graph. Unique per graph; the join key between sockets, hops, neighbours, DNS answers and data. `Name` is display only. |
| node | `NetworkGraph.Node`, `NetworkGraph.Node.Kind` | One named thing: Host, Interface, Subnet, Route, Hop, Connection, Process, RemoteHost, Cloud or Asn. |
| edge | `NetworkGraph.Edge`, `NetworkGraph.Edge.Kind` | A typed relation between two Ids: `Contains`, `RoutesTo`, `HopsTo`, `ConnectsTo`, `OwnedBy`, `ResolvesTo`, `BelongsTo`. |
| finding | `NetworkGraph.Finding`, `NetworkGraph.Finding.Finding`, `NetworkGraph.Graph.Findings` | Something the graph shows that deserves a look, reported as data rather than thrown. |
| graph | `ConvertTo-NetworkGraph`, `NetworkGraph.Graph`, `NetworkGraph.Graph.Root` | Nodes, edges and findings built from any mix of calculate and observe output, rooted at the host. |
| row | `NetworkGraph.Hop`, `NetworkGraph.Port`, `NetworkGraph.Neighbor`, `NetworkGraph.DnsRecord` | One line of a wrapped tool's answer, parsed into a typed object before any graph is built. |
| Source | `NetworkGraph.Node.Source`, `NetworkGraph.Hop.Source`, `NetworkGraph.IPAddressInfo.Source` | The exact command line, .NET expression or data file citation that produced a row or node; pasteable into a fresh shell. |
| tool | `NetworkGraph.Hop.Tool`, `Trace-NetworkPath`, `Invoke-NetworkScan` | What an observe command ran: the native tool when present, else the .NET floor; `-Tool` (Auto, Native or DotNet) chooses. |
| data file | `Get-NetworkGraphData`, `NetworkGraph.DataFile`, `data/special-use.json` | One bundled or harvested JSON file of reference data, with its kind, pulled date and maximum age. |
| sources | `NetworkGraph.DataFile.Sources`, `NetworkGraph.DataSource`, `NetworkGraph.DataSource.Url` | The pages each data file was copied or harvested from, each with a URL, a title and the date it was pulled. |
| reservation | `Get-Subnet`, `NetworkGraph.ReservedAddress.Role`, `data/cloud-reservations.json` | An address in a subnet that a cloud (or plain IP) keeps for itself, with the role the vendor's page gives it. |
| cloud range | `Test-IPAddress`, `NetworkGraph.IPAddressInfo.CloudPrefix`, `data/cloud-ranges.json.gz` | A prefix a cloud publishes as its own, with the service and region behind it; what puts a RemoteHost in a Cloud. |

## Facts and opinions

**Facts** are copied from their source and never edited: tool output (each row with its `Source`), the IANA special-purpose and port registries (`data/special-use.json`, `data/ports.json`), the IEEE OUI list (`data/oui.json`), the clouds' published ranges (`data/cloud-ranges.json.gz`), the clouds' subnet reservation rules (`data/cloud-reservations.json`, written by hand from the pages it cites, row by row), and RDAP answers. When a fact is missing or does not join, that is a finding or an empty field, never a guess.

**Opinions** are data or code with reasons:

- `data/ip-sources.json` is the choice of which public endpoints `Get-ExternalIpAddress` asks and which RDAP service it uses.
- The finding rules (what counts as `NonCloudPublicConnection` or `WildcardListener`) and which path `-Tool Auto` takes per command and platform are judgement calls recorded in [docs/design.md](docs/design.md).
- Opinions never change a fact: a finding never removes a node or an edge, and choosing `-Tool DotNet` changes `Source`, not the Ids of what was seen.

## Not here yet

| Planned | What it adds | Target |
|---|---|---|
| IPv6 first | Cloud rules, examples and manual checks for IPv6 (the arithmetic and parsers already handle it). | not scheduled |
| TerraformGraph join | `azurerm_subnet` and `aws_subnet` nodes from TerraformGraph read into `Test-SubnetOverlap`, so declared and observed subnets meet. | not scheduled |
| shared view | An HTML view drawn by TerraformGraph's renderer, once the two remaining shape differences are closed. | not scheduled |
| IPAM export | Plans and observed subnets written in a form an IPAM tool imports. | not scheduled |
| SNMP | Reading neighbours and interfaces from devices other than the host. | not scheduled |
