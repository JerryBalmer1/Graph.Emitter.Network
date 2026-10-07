---
name: networkgraph
description: Load when calculating subnets (Azure, AWS, GCP reservations, VLSM plans, overlaps), classifying IP or MAC addresses, observing a host's network (connections, routes, neighbours, traces, ports, DNS) or graphing it in PowerShell with the NetworkGraph module.
---

# NetworkGraph

PowerShell 7.4+ module in three groups. Windows and Linux are supported; macOS is untested. IPv4 is the v1 target; IPv6 works through the same code.

```powershell
Import-Module NetworkGraph                                  # installed copy
Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force   # from a clone
```

## Calculate (offline, deterministic)

- `Get-Subnet` — `-Cidr` (pipeline) | `-Address -PrefixLength` | `-Address -Mask`; `-Cloud None|Azure|AWS|GCP` → `NetworkGraph.Subnet` (Cidr, Version, Network, Broadcast, FirstUsable, LastUsable, Usable, Mask, Wildcard, PrefixLength, Cloud, Reserved [Ip, Role, Source], Gateway, BelowCloudMinimum). Azure and AWS /24 = 251 usable, GCP 252, None 254.
- `New-SubnetPlan` — `-Cidr` with `-PrefixLength` (equal split) | `-Hosts n,n` | `-Requirement @{ name = hosts }`; `-Cloud` → `NetworkGraph.SubnetPlan` (Parent, Cloud, Subnets with Name, Parent, RequestedHosts, Remaining). Error `PlanDoesNotFit` names the shortfall.
- `Test-SubnetOverlap` — `-Cidr a,b,c` (`-OverlapOnly`) → rows Left, Right, Relation `Overlaps|Contains|ContainedBy|Disjoint`.
- `Get-SubnetParent` / `Get-SubnetChildren` — containment over a list (`-In`, `-Recurse`) → rows Cidr, Parent.
- `ConvertTo-SubnetMask` / `ConvertFrom-SubnetMask` — IPv4 only.
- `Test-IPAddress` — flags IsPrivate, IsLoopback, IsLinkLocal, IsCgnat, IsMulticast, IsDocumentation, IsReserved; Scope; Source (RFC); Cloud, Service, Region, Asn, Owner from the bundled cloud ranges.
- `Get-MacAddressVendor` — Oui, Vendor, IsLocallyAdministered, IsMulticast, IsRandomized. A randomised (locally-administered) MAC has no vendor.

## Observe (wraps installed tools)

All take `-Tool Auto|Native|DotNet` (Auto: native when installed, else the .NET floor). Every row has `Source`: the tool and exact command line. Nothing is bundled; nmap is used only if installed.

- `Test-NetworkPath` (ping), `Trace-NetworkPath` (tracert/pathping, mtr/traceroute; `-NativeTool`), `Test-NetworkPort` (`-Port`, `-Protocol Tcp|Udp`, `-Timeout`), `Invoke-NetworkScan` (nmap -oX, else TCP connect; `-ThrottleLimit`; accepts CIDR targets).
- `Get-NetworkConnection` (`-Protocol`, `-State`, `-Resolve` adds RemoteHost, Cloud, Service, Asn, Owner), `Get-NetworkNeighbor`, `Get-NetworkRoute`, `Get-NetworkInterface`, `Get-NetworkHost` (one object: interfaces, routes, gateway, DNS, firewall).
- `Resolve-NetworkName` (`-Type A|AAAA|PTR|MX|TXT|NS|CNAME|SRV`, `-Server`; the .NET floor answers A, AAAA, PTR only).
- `Get-ExternalIpAddress` (`-Rdap` adds Network, Owner, Country, Cidr, Asn when the registry has it). No BGP: a host cannot see routing beyond its own table and traces.

Only scan hosts you are allowed to scan. Never add tools or flags whose purpose is evading a control.

Before sharing captured output (a bug report, a test fixture, a pasted Source line), scrub it without changing its format: keep the vendor half of every LAN MAC and replace the device half with `00-00-nn` (MACs inside EUI-64 IPv6 addresses `...ff:fe..` too); replace every public IP that belongs to the capturing host (its external address, its own global IPv6 addresses, the address an RDAP lookup was made for) with a documentation address (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24, 2001:db8::/32); replace host names that identify a person or site; and replace first-party ISP infrastructure (the resolver addresses and names the host was given, the first public hops after the gateway, adapter names that identify a device model) with documentation addresses and generic names.

## Graph and data

- `ConvertTo-NetworkGraph` — any mix of the above → `NetworkGraph.Graph` (Root, Nodes, Edges, Findings, NodeCount, EdgeCount, FindingCount). Node kinds Host, Interface, Subnet, Route, Hop, Connection, Process, RemoteHost, Cloud, Asn; edges Contains, RoutesTo, HopsTo, ConnectsTo, OwnedBy, ResolvesTo, BelongsTo (properties From, To, Kind, as TerraformGraph); findings SubnetOverlap, BelowCloudMinimum, NonCloudPublicConnection, WildcardListener, RouteWithoutInterface. Offline.
- `Get-NetworkGraphData` — data files with sources and pulled dates (`-Kind`, `-Sources`).
- `Update-NetworkGraphData` — refresh SpecialUse, CloudRanges, Oui, Ports into the user cache (network). Cloud ranges change weekly.

## Recipes

```powershell
Get-Subnet 10.0.0.0/24 -Cloud Azure
New-SubnetPlan 10.0.0.0/22 -Hosts 250, 120, 60, 25 -Cloud AWS
Get-NetworkConnection -State Established -Resolve | Format-Table RemoteIp, RemoteHost, Cloud, Service, ProcessName
@(Get-NetworkHost; Get-NetworkConnection -Resolve) | ConvertTo-NetworkGraph | Select-Object -ExpandProperty Findings
```
