# NetworkGraph

```powershell
PS> Get-Subnet 10.0.0.0/24 -Cloud Azure

Cidr        : 10.0.0.0/24
Cloud       : Azure
FirstUsable : 10.0.0.4
LastUsable  : 10.0.0.254
Usable      : 251
Gateway     : 10.0.0.1

PS> (Get-Subnet 10.0.0.0/24 -Cloud Azure).Reserved | Format-Table Ip, Role

Ip         Role
--         ----
10.0.0.0   Network address
10.0.0.1   Default gateway
10.0.0.2   Azure DNS mapping
10.0.0.3   Azure DNS mapping
10.0.0.255 Broadcast address
```

```powershell
PS> Get-NetworkConnection -Resolve | ConvertTo-NetworkGraph

Root   NodeCount EdgeCount FindingCount
----   --------- --------- ------------
myhost       549      1103           78
```

IPv4 is the v1 target. IPv6 runs through the same code and is tested, but the cloud rules, the examples and the manual checks are IPv4.

NetworkGraph wraps the network tools already installed on the machine and never ships a binary: no nmap, no DLL, nothing compiled, and nothing whose purpose is evading a control.

## What it is

A PowerShell 7.4+ module in three groups, split by how fast each one ages:

| Group | Commands | Ages when |
|---|---|---|
| **Calculate**: offline, deterministic | `Get-Subnet`, `New-SubnetPlan`, `Test-SubnetOverlap`, `Get-SubnetParent`, `Get-SubnetChildren`, `ConvertTo-SubnetMask`, `ConvertFrom-SubnetMask`, `Test-IPAddress`, `Get-MacAddressVendor` | a cloud changes its reservation rules, or a registry adds a row |
| **Observe**: wraps what is on the box | `Test-NetworkPath`, `Trace-NetworkPath`, `Test-NetworkPort`, `Get-NetworkConnection`, `Get-NetworkNeighbor`, `Get-NetworkRoute`, `Get-NetworkInterface`, `Resolve-NetworkName`, `Get-ExternalIpAddress`, `Get-NetworkHost`, `Invoke-NetworkScan` | an OS or tool changes its output |
| **Graph and data** | `ConvertTo-NetworkGraph`, `Get-NetworkGraphData`, `Update-NetworkGraphData` | the published IP ranges and registries change (weekly for cloud ranges) |

Every exported command has full help (`Get-Help Get-Subnet -Full`), and every fixed-vocabulary parameter tab-completes (`-Cloud`, `-Tool`, `-Protocol`, `-Type`, `-Kind`, ...).

## Install and import

```powershell
Import-Module .\src\NetworkGraph\NetworkGraph.psd1     # from a clone
```

Requires PowerShell 7.4 or later. Windows and Linux are tested; macOS is untested.

## Calculate

```powershell
Get-Subnet 10.0.0.0/24 -Cloud AWS                      # 251 usable; GCP 252; None 254
Get-Subnet -Address 192.168.1.77 -Mask 255.255.255.192  # 192.168.1.64/26
New-SubnetPlan 10.0.0.0/22 -Hosts 250, 120, 60, 25      # VLSM, largest first
New-SubnetPlan 10.1.0.0/16 -Requirement @{ web = 200; app = 400 } -Cloud Azure
Test-SubnetOverlap 10.0.0.0/24, 10.0.0.128/25, 10.1.0.0/16 -OverlapOnly
Test-IPAddress 100.64.0.1, 20.42.65.92                  # CGNAT; Azure and the service tag
Get-MacAddressVendor 00-15-5D-01-02-03                  # Microsoft Corporation
```

Cloud rules (`data/cloud-reservations.json`, each row citing the vendor page): Azure and AWS reserve the first four addresses and the last, GCP the first two, the second-to-last and the last. Smallest subnet: Azure /29, AWS /28, GCP /29. A /31 under `-Cloud None` has two usable addresses (RFC 3021).

`New-SubnetPlan` adds the cloud's reservations to each host count, rounds up to a power of two, places the largest first, and when the plan does not fit says by how many addresses.

MAC vendors: Windows, iOS and Android randomise the MAC address they show each network. A randomised address sets the locally-administered bit and belongs to no vendor, so the vendor is only trustworthy when `IsLocallyAdministered` is `$false`; `Get-MacAddressVendor` returns no vendor otherwise.

## Observe

Each observe command uses the native tool when it is installed, falls back to a .NET floor when it is not, and takes `-Tool Auto|Native|DotNet` to force one. The exception is `Test-NetworkPort`, whose Auto is the .NET path because Test-NetConnection ignores `-Timeout` and spends about 20 seconds on a filtered port. Every row has a `Source` property naming the tool and the exact command line that produced it, so output can be checked by hand.

| Command | Windows native | Linux native | .NET floor |
|---|---|---|---|
| `Test-NetworkPath` | ping.exe | ping | `Ping` |
| `Trace-NetworkPath` | tracert, or pathping with `-NativeTool pathping` | mtr --json, else traceroute | TTL-stepped `Ping` |
| `Test-NetworkPort` | Test-NetConnection (`-Tool Native` only) | nc -z (`-Tool Native` only) | `TcpClient` (honours `-Timeout`; what Auto uses) |
| `Get-NetworkConnection` | Get-NetTCPConnection, Get-NetUDPEndpoint | ss -tunap | `IPGlobalProperties` (no process) |
| `Get-NetworkNeighbor` | Get-NetNeighbor, else arp -a | ip -j neigh, else arp -a | /proc/net/arp (Linux only) |
| `Get-NetworkRoute` | Get-NetRoute | ip -j route | derived from interface addresses |
| `Get-NetworkInterface` | Get-NetIPConfiguration | ip -j addr | `NetworkInterface` |
| `Resolve-NetworkName` | Resolve-DnsName | dig, else nslookup | `Dns` (A, AAAA, PTR only) |
| `Get-ExternalIpAddress` | curl | curl | `HttpClient` |
| `Invoke-NetworkScan` | nmap | nmap | `TcpClient` |

Structured output is parsed where the tool offers it (`ip -j`, `mtr --json`, `nmap -oX`, PowerShell objects). Text output (ping, tracert, pathping, traceroute, ss, arp, dig, nslookup, nc, ufw) is read with regular expressions pinned by fixture tests captured from real runs on each platform; English output only.

`Invoke-NetworkScan` runs nmap with `-oX` if it is on PATH and otherwise falls back to TCP connect tests, and NetworkGraph bundles no nmap, no scripts folder and adds no OS-fingerprinting flags by default.

What a host can and cannot see about routing: it sees its own route table, the hops a trace reveals, and what registries (RDAP) say about an address. It cannot see BGP, the prefixes other networks announce and the paths between them, and NetworkGraph does no BGP lookup. `Asn` on a cloud address is that cloud's primary network; `Get-ExternalIpAddress -Rdap` reports an ASN only when the registry publishes one.

## Graph

```powershell
$graph = @(Get-NetworkHost; Get-NetworkConnection -Resolve; Trace-NetworkPath 1.1.1.1) | ConvertTo-NetworkGraph
$graph.Nodes | Group-Object Kind
$graph.Findings | Format-Table Finding, NodeId, Detail
```

Nodes (Host, Interface, Subnet, Route, Hop, Connection, Process, RemoteHost, Cloud, Asn), edges (Contains, RoutesTo, HopsTo, ConnectsTo, OwnedBy, ResolvesTo, BelongsTo) and findings (SubnetOverlap, BelowCloudMinimum, NonCloudPublicConnection, WildcardListener, RouteWithoutInterface). The property names match TerraformGraph's `ConvertTo-TerraformResourceGraph`; [docs/graph-shape.md](docs/graph-shape.md) is the contract.

## Data

`Get-NetworkGraphData` lists the data files with their sources and pulled dates; `Get-NetworkGraphData -Sources` lists every source URL.

| Kind | File | From |
|---|---|---|
| CloudReservations | cloud-reservations.json | Microsoft, AWS and Google subnet docs (by hand) |
| SpecialUse | special-use.json | IANA IPv4 and IPv6 special-purpose registries (RFC 6890) plus multicast |
| CloudRanges | cloud-ranges.json.gz | Azure Service Tags, AWS ip-ranges.json, Google goog.json and cloud.json |
| Oui | oui.json | IEEE MA-L assignments |
| Ports | ports.json | IANA service names and port numbers |
| IpSources | ip-sources.json | the HTTPS endpoints Get-ExternalIpAddress and -Rdap use (by hand) |

`Update-NetworkGraphData` refreshes the harvested kinds into `$env:LOCALAPPDATA\NetworkGraph\data`, which then wins over the bundled copy. Cloud ranges change weekly; refresh them before trusting a Cloud column.

## Not here yet

- IPv6 as a first-class target (cloud rules, examples, manual checks).
- Reading `azurerm_subnet` and `aws_subnet` nodes from TerraformGraph output into `Test-SubnetOverlap`.
- An HTML view (shares TerraformGraph's renderer).
- IPAM export.
- SNMP.

## Development

```powershell
Invoke-Build            # Test: Pester in a fresh process
Invoke-Build Analyze    # PSScriptAnalyzer
Invoke-Build Assemble   # one-file module in dist/
Invoke-Build UpdateData # harvest, then promote to src/NetworkGraph/data
Invoke-Build CheckData  # every data file sourced and within its maximum age
```

`manual-check-list.md` holds the paste-and-check steps.

Licensed under the Apache License, Version 2.0 ([LICENSE](LICENSE), [NOTICE](NOTICE)).
