> **Built as an ontology layer for AI agents.** If that is why you are here, read [ONTOLOGY.md](ONTOLOGY.md).

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&height=220&section=header&color=0:0B2530,45:12708A,100:2BB3A3&text=Graph.Emitter.Network&fontSize=52&fontColor=FFFFFF&fontAlignY=38&desc=Subnet%20math%2C%20the%20network%20tools%20you%20already%20have%2C%20and%20a%20graph%20of%20what%20a%20host%20can%20see&descSize=16&descAlignY=62&animation=fadeIn" alt="Graph.Emitter.Network" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PowerShell-7.4%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell 7.4+" />
  <img src="https://img.shields.io/badge/Pester-6.1%2B-0078D4?style=for-the-badge" alt="Pester 6.1+" />
  <img src="https://img.shields.io/badge/Windows%20%7C%20Linux-tested-12708A?style=for-the-badge" alt="Windows and Linux tested" />
  <img src="https://img.shields.io/badge/License-Apache%202.0-D22128?style=for-the-badge" alt="Apache License 2.0" />
</p>

<p align="center">
  <sub><a href="https://github.com/kyechan99/capsule-render">Above was created by capsule-render</a></sub>
</p>

Subnet math with cloud reservations, auditable wrappers over the network tools already installed, and a graph of what a host can see.

**In CI**, one line fails the build when any two subnets in a plan overlap:

```powershell
pwsh -NoProfile -Command "Import-Module Graph.Emitter.Network; if (Test-SubnetOverlap -Cidr (Get-Content .\subnets.txt) -OverlapOnly) { exit 1 }"
```

Exit code 0: no two prefixes in `subnets.txt` (one CIDR per line) share an address. Exit code 1: at least one pair overlaps. A line that is not a prefix, or a missing file, is a terminating error, which also exits 1. `Test-SubnetOverlap` is offline: no network, no tool runs.

> **Requires PowerShell 7.4+.** Agents, skills, and tool runners should use 7.4 (or later) so `$ErrorActionPreference = 'Stop'` is a first-class default you can rely on. On older hosts a failed lookup is often a *non-terminating* error: the pipeline keeps going, the agent reads "success," and it never gets a chance to correct the address or the tool. 7.4 is the line this module draws so an agent actually *sees* the failure and can fix it.

There was no PowerShell module that did cloud-aware subnet math and also read the host's own network through the tools already on it, with every row saying which command produced it, so this module exists. It wraps ping, tracert, pathping, traceroute, mtr, ss, arp, ip, dig, nslookup, curl, nmap and the Windows networking cmdlets, falls back to .NET when a tool is missing, and never ships a binary: no nmap, no DLL, nothing compiled, and nothing whose purpose is evading a control.

IPv4 is the v1 target. IPv6 runs through the same code and is tested, but the cloud rules, the examples and the manual checks are IPv4.

Source version **0.3.0**. Not yet published to the PowerShell Gallery: install from a clone (see [Install](#install)).

---

## Requirements

- OS: **Windows and Linux** are tested. macOS is untested: the module imports with one warning, and `Get-NetworkNeighbor` says it has no .NET floor there.
- PowerShell **7.4 or later** (enforced by the module manifest)
- Nothing else. Each observe command uses the native tool when it is installed (nmap, mtr, traceroute, dig, nc and so on) and a .NET floor when it is not; see [Observe](#observe).

## Setup

- Clone this repo; the module is not on the PowerShell Gallery yet.
- Import the module from `src`. No build step, no admin rights.
- Try `Get-Subnet 10.0.0.0/24 -Cloud Azure`, then `Get-NetworkHost`.

## Downloads & Links

- Homepage: https://github.com/JerryBalmer1/Graph.Emitter.Network
- Release notes: `ReleaseNotes` in [src/Graph.Emitter.Network/Graph.Emitter.Network.psd1](src/Graph.Emitter.Network/Graph.Emitter.Network.psd1)
- Graph contract: [docs/graph-shape.md](docs/graph-shape.md)

---

## Install

From a clone:

```powershell
Import-Module .\src\Graph.Emitter.Network\Graph.Emitter.Network.psd1
```

<!--
### Once on the Gallery

Restore this, and a Gallery badge and link at the top, when Graph.Emitter.Network is published:

```powershell
Install-Module -Name Graph.Emitter.Network -Scope CurrentUser
Import-Module Graph.Emitter.Network
```
-->

## Examples

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

The commands come in three groups, split by how fast each one ages:

| Group | Commands | Ages when |
|---|---|---|
| **Calculate**: offline, deterministic | `Get-Subnet`, `New-SubnetPlan`, `Test-SubnetOverlap`, `Get-SubnetParent`, `Get-SubnetChildren`, `ConvertTo-SubnetMask`, `ConvertFrom-SubnetMask`, `Test-IPAddress`, `Get-MacAddressVendor` | a cloud changes its reservation rules, or a registry adds a row |
| **Observe**: wraps what is on the box | `Test-NetworkPath`, `Trace-NetworkPath`, `Test-NetworkPort`, `Get-NetworkConnection`, `Get-NetworkNeighbor`, `Get-NetworkRoute`, `Get-NetworkInterface`, `Resolve-NetworkName`, `Get-ExternalIpAddress`, `Get-NetworkHost`, `Invoke-NetworkScan` | an OS or tool changes its output |
| **Graph and data** | `ConvertTo-NetworkGraph`, `Get-NetworkGraphData`, `Update-NetworkGraphData` | the published IP ranges and registries change (weekly for cloud ranges) |

Every exported command has full help (`Get-Help Get-Subnet -Full`), and every fixed-vocabulary parameter tab-completes (`-Cloud`, `-Tool`, `-Protocol`, `-Type`, `-Kind`, ...). `manual-check-list.md` has a paste-and-check block for every command and parameter set (sections 2 to 24).

## Calculate

```powershell
Get-Subnet 10.0.0.0/24 -Cloud AWS                      # 251 usable; GCP 252; None 254
Get-Subnet -Address 192.168.1.77 -Mask 255.255.255.192  # 192.168.1.64/26
New-SubnetPlan 10.0.0.0/22 -Hosts 250, 120, 60, 25      # VLSM, largest first
New-SubnetPlan 10.1.0.0/16 -Requirement @{ web = 200; app = 400 } -Cloud Azure
New-SubnetPlan 10.0.0.0/24 -PrefixLength 26 -Cloud Azure  # four /26s, 59 usable each
Test-SubnetOverlap 10.0.0.0/24, 10.0.0.128/25, 10.1.0.0/16 -OverlapOnly  # 10.0.0.0/24 Contains 10.0.0.128/25
Get-SubnetParent 10.0.1.7 -In 10.0.0.0/16, 10.0.1.0/24  # 10.0.1.7/32 under 10.0.1.0/24
Get-SubnetChildren 10.0.0.0/16 -In 10.0.1.0/24, 10.0.1.128/25 -Recurse
ConvertTo-SubnetMask 26                                 # 255.255.255.192
ConvertFrom-SubnetMask 255.255.0.0                      # 16
Test-IPAddress 100.64.0.1, 20.42.65.92                  # Cgnat; Azure, service OneDsCollector
Get-MacAddressVendor 00-15-5D-01-02-03                  # Microsoft Corporation
```

Cloud rules (`data/cloud-reservations.json`, each row citing the vendor page): Azure and AWS reserve the first four addresses and the last, GCP the first two, the second-to-last and the last. Smallest subnet: Azure /29, AWS /28, GCP /29. A /31 under `-Cloud None` has two usable addresses (RFC 3021).

`New-SubnetPlan` adds the cloud's reservations to each host count, rounds up to a power of two, places the largest first, and when the plan does not fit says by how many addresses.

MAC vendors: Windows, iOS and Android randomise the MAC address they show each network. A randomised address sets the locally-administered bit and belongs to no vendor, so the vendor is only trustworthy when `IsLocallyAdministered` is `$false`; `Get-MacAddressVendor` returns no vendor otherwise.

### IPv6 first (Planned)

Cloud rules, examples and manual checks for IPv6. The arithmetic and the parsers already handle it.

## Observe

Each observe command uses the native tool when it is installed, falls back to a .NET floor when it is not, and takes `-Tool Auto|Native|DotNet` to force one. The exceptions: `Test-NetworkPort`, whose Auto is the .NET path because Test-NetConnection ignores `-Timeout` and spends about 20 seconds on a filtered port; and `Test-NetworkPath` and `Trace-NetworkPath` on Windows, whose Auto is the .NET path because ping.exe, tracert and pathping print in the Windows display language and .NET's `Ping` uses the same ICMP API. Every row has a `Source` property naming the tool and the exact command line that produced it, so output can be checked by hand.

```powershell
Get-NetworkHost                                         # name, OS, interfaces, routes, DNS, firewall state
Get-NetworkInterface
Get-NetworkRoute -AddressFamily IPv4
Get-NetworkNeighbor                                     # ARP and NDP, with the vendor of each MAC
Get-NetworkConnection -Protocol Tcp -State Listen
Get-NetworkConnection -Resolve                          # adds reverse DNS, Cloud, Service, Asn, Owner
Test-NetworkPath 1.1.1.1 -Count 2
Trace-NetworkPath 1.1.1.1
Trace-NetworkPath 1.1.1.1 -Tool Native                  # tracert on Windows, mtr or traceroute on Linux
Test-NetworkPort 1.1.1.1 -Port 443, 53
Invoke-NetworkScan 127.0.0.1 -Port 22, 80, 135, 445     # nmap if on PATH, else TcpClient
Resolve-NetworkName example.com -Type MX -Server 1.1.1.1
Get-ExternalIpAddress -Rdap                             # three endpoints must agree; RDAP for the holder
```

| Command | Windows native | Linux native | .NET floor |
|---|---|---|---|
| `Test-NetworkPath` | ping.exe (`-Tool Native` only) | ping | `Ping` (what Auto uses on Windows) |
| `Trace-NetworkPath` | tracert, or pathping with `-NativeTool pathping` (`-Tool Native` or `-NativeTool` only) | mtr --json, else traceroute | TTL-stepped `Ping` (what Auto uses on Windows) |
| `Test-NetworkPort` | Test-NetConnection (`-Tool Native` only) | nc -z (`-Tool Native` only) | `TcpClient` (honours `-Timeout`; what Auto uses) |
| `Get-NetworkConnection` | Get-NetTCPConnection, Get-NetUDPEndpoint | ss -tunap | `IPGlobalProperties` (no process) |
| `Get-NetworkNeighbor` | Get-NetNeighbor, else arp -a | ip -j neigh, else arp -a | /proc/net/arp (Linux only) |
| `Get-NetworkRoute` | Get-NetRoute | ip -j route | derived from interface addresses |
| `Get-NetworkInterface` | Get-NetIPConfiguration | ip -j addr | `NetworkInterface` |
| `Resolve-NetworkName` | Resolve-DnsName | dig, else nslookup | `Dns` (A, AAAA, PTR only) |
| `Get-ExternalIpAddress` | curl | curl | `HttpClient` |
| `Get-NetworkHost` | the commands above, Get-NetFirewallProfile, Windows Security Center | the commands above, ufw.conf, ufw, firewall-cmd | the floors above |
| `Invoke-NetworkScan` | nmap | nmap | `TcpClient` |

Interface, route and neighbour rows carry `InterfaceKey`, the identifier the graph keys an interface on because the alias can be renamed: the interface GUID on Windows, the ifindex on Linux (stable for one boot only). Get-NetRoute, Get-NetNeighbor, arp, `ip route` and `ip neigh` name an interface by index or device name only, so `Get-NetworkRoute` and `Get-NetworkNeighbor` look the key up at the same moment and add that lookup to `Source`: `[System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()` on Windows, `Get-Content /sys/class/net/*/ifindex` on Linux.

Structured output is parsed where the tool offers it (`ip -j`, `mtr --json`, `nmap -oX`, PowerShell objects). Text output (ping, tracert, pathping, traceroute, ss, arp, dig, nslookup, nc, ufw) is read with regular expressions pinned by fixture tests captured from real runs on each platform; English output only. On Linux and macOS native tools run with `LC_ALL=C`; output a parser does not recognise is an error that names `-Tool DotNet`, never an empty or "down" answer. A native tool that exits with a code its command does not expect, or times out, is an error carrying its stderr and command line.

`Invoke-NetworkScan` runs nmap with `-oX - -n -Pn -p` if it is on PATH and otherwise falls back to TCP connect tests (at most 4096 addresses). Graph.Emitter.Network bundles no nmap, no scripts folder, and adds no version, OS-detection, timing or evasion flags. Scan only networks you own or are authorised to test.

What a host can and cannot see about routing: it sees its own route table, the hops a trace reveals, and what registries (RDAP) say about an address. It cannot see BGP, the prefixes other networks announce and the paths between them, and Graph.Emitter.Network does no BGP lookup. `Asn` on a cloud address is that cloud's primary network; `Get-ExternalIpAddress -Rdap` reports an ASN only when the registry publishes one.

### SNMP (Planned)

Reading neighbours and interfaces from devices other than the host.

## Graph

```powershell
$graph = @(Get-NetworkHost; Get-NetworkConnection -Resolve; Trace-NetworkPath 1.1.1.1) | ConvertTo-NetworkGraph
$graph.Nodes | Group-Object Kind
$graph.Findings | Format-Table Finding, NodeId, Detail

# Plans and subnets alone make a host-less graph, with overlaps and too-small subnets as findings.
@(Get-Subnet 10.0.0.0/24 -Cloud Azure; Get-Subnet 10.0.0.128/25 -Cloud Azure) | ConvertTo-NetworkGraph
```

Every edge carries the `Source` of the row that asserted it, and Interface and Route Ids use the interface key, so renaming an adapter does not fork its node. On this machine on 2026-10-08 (GUID replaced as in the test fixtures):

```powershell
PS> $graph = @(Get-NetworkInterface; Get-NetworkRoute -AddressFamily IPv4) | ConvertTo-NetworkGraph -HostName testhost
PS> $graph.Edges | Where-Object Kind -eq RoutesTo | Format-Table From, To, Source

From                                                                        To          Source
----                                                                        --          ------
testhost/route/0.0.0.0/0/192.168.0.1/{00000000-0000-0000-0000-000000000016} 192.168.0.1 Get-NetRoute; [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()

PS> $graph.Nodes | Where-Object Name -eq 'Wi-Fi' | Format-List Id, Name, InterfaceKey, Source

Id           : testhost/if/{00000000-0000-0000-0000-000000000016}
Name         : Wi-Fi
InterfaceKey : {00000000-0000-0000-0000-000000000016}
Source       : Get-NetIPConfiguration -All
```

Nodes (Host, Interface, Subnet, Route, Hop, Connection, Process, RemoteHost, Cloud, Asn), edges (Contains, RoutesTo, HopsTo, ConnectsTo, OwnedBy, ResolvesTo, BelongsTo) and findings (SubnetOverlap, BelowCloudMinimum, NonCloudPublicConnection, WildcardListener, RouteWithoutInterface). On this machine on 2026-10-07 the first example gave 345 Connection, 75 Process, 53 Route, 31 RemoteHost, 10 Interface, 7 Hop, 3 Cloud, 3 Asn, 2 Subnet and 1 Host nodes, with 26 NonCloudPublicConnection and 26 WildcardListener findings. The property names match TerraformGraph's `ConvertTo-TerraformResourceGraph`; [docs/graph-shape.md](docs/graph-shape.md) is the contract, and lists the three differences that remain (edges here carry `Source`). [ONTOLOGY.md](ONTOLOGY.md#terminology) defines each node and edge Kind.

### Shared view with TerraformGraph (Planned)

An HTML view drawn by the same renderer as TerraformGraph, and `azurerm_subnet` and `aws_subnet` nodes from TerraformGraph output read into `Test-SubnetOverlap`.

### IPAM export (Planned)

Plans and observed subnets written in a form an IPAM tool imports.

## Data

`Get-NetworkGraphData` lists the data files with their sources and pulled dates; `Get-NetworkGraphData -Sources` lists every source URL; `Get-NetworkGraphData -Kind CloudReservations` returns one parsed document.

| Kind | File | From |
|---|---|---|
| CloudReservations | cloud-reservations.json | Microsoft, AWS and Google subnet docs (by hand) |
| SpecialUse | special-use.json | IANA IPv4 and IPv6 special-purpose registries (RFC 6890) plus multicast |
| CloudRanges | cloud-ranges.json.gz | Azure Service Tags, AWS ip-ranges.json, Google goog.json and cloud.json |
| Oui | oui.json | IEEE MA-L assignments |
| Ports | ports.json | IANA service names and port numbers |
| IpSources | ip-sources.json | the HTTPS endpoints Get-ExternalIpAddress and -Rdap use (by hand) |

`Update-NetworkGraphData` refreshes the harvested kinds into `$env:LOCALAPPDATA\NetworkGraph\data`, which then wins over the bundled copy; `-Path` writes somewhere else instead, and `-WhatIf` shows where it would write. Cloud ranges change weekly; refresh them before trusting a Cloud column.

```powershell
Update-NetworkGraphData -Kind CloudRanges -WhatIf
Update-NetworkGraphData -Kind SpecialUse -Path $env:TEMP\networkgraph-data -PassThru
```

## Agent skills

The module ships an agent skill at `skills/networkgraph/SKILL.md` inside the module folder, in the open Agent Skills format: YAML front matter with `name` and `description`, then a Markdown body covering the commands in their three groups with their parameter sets and output types, and recipes. Copy the folder into a repository's `.claude/skills/` (or another tool's skills folder) to give an agent the skill.

### Install command (Planned)

A command that copies the skill into a repository for each agent tool and reports which copies are stale, as TerraformGraph's `Install-TerraformGraphSkill` does. Not built yet; copy the folder by hand.

---

## Build and test (contributors)

```powershell
Invoke-Build            # Test: Pester in a fresh process, no network
Invoke-Build Analyze    # PSScriptAnalyzer
Invoke-Build Assemble   # one-file module in dist/Graph.Emitter.Network/<version>
Invoke-Build UpdateData # harvest, then promote to src/Graph.Emitter.Network/data (network)
Invoke-Build CheckData  # every data file sourced and within its maximum age
```

Function code is one function per file, named for the function: `src/Graph.Emitter.Network/Public/<Verb-Noun>.ps1` for an exported command, `src/Graph.Emitter.Network/Private/<Verb-Noun>.ps1` for a helper. Edit the file named for the function, never `Graph.Emitter.Network.psm1`: it is state and wiring only, and `Invoke-Build Assemble` builds the single psm1 that ships.

Tests never call the network or a real tool unless tagged `Live`: `$env:NETWORKGRAPH_LIVE = 1; Invoke-Pester -Path .\tests -TagFilter Live` runs those. `manual-check-list.md` holds the paste-and-check steps.

## Disclaimer

This project is independent. It is not affiliated with Microsoft, Amazon Web Services, Google, IANA, IEEE or the Nmap Project.

## License

Graph.Emitter.Network is licensed under the [Apache License 2.0](LICENSE) ([NOTICE](NOTICE)).

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&height=120&section=footer&color=0:2BB3A3,55:12708A,100:0B2530&text=Graph.Emitter.Network&fontSize=28&fontColor=FFFFFF&fontAlignY=70&animation=fadeIn" alt="" />
</p>
