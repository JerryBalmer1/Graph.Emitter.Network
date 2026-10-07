# Design notes

Judgement calls made while building 0.1.0, each with what was rejected and why. Append; do not rewrite an earlier note.

## 1. One BigInteger path for IPv4 and IPv6

An address is its bytes read as an unsigned big-endian `System.Numerics.BigInteger` (`ConvertTo-NetworkGraphIpValue`); a prefix is `Network`, `Last`, `Size` in the same type (`Resolve-NetworkGraphPrefix`). IPv4 and IPv6 share every line of subnet math. Rejected: `[uint32]` for IPv4 plus a separate IPv6 path, which doubles the code the tests must cover. Cost: PowerShell's `++` does not work on BigInteger; write `$v = $v + 1`.

`Usable` is a BigInteger for both versions (a /48 has 2^80 addresses). It compares with ordinary integers (`-eq 251`) as expected.

## 2. Broadcast, /31 and /32

`Broadcast` is set for IPv4 up to /30 only. A /31 is a point-to-point link with two usable addresses and no reserved ones (RFC 3021); a /32 is one address. IPv6 has no broadcast, and under `-Cloud None` reserves nothing (the subnet-router anycast address of RFC 4291 is usable as an address).

## 3. Cloud reservations are data, applied per IP version

`data/cloud-reservations.json` holds each cloud's reserved offsets (from the first or last address), gateway, smallest and largest subnet, and which IP versions the list applies to. AWS documents the same five reservations for IPv6, so AWS applies to both; Azure and GCP document IPv4 only, so an IPv6 subnet under them uses None with a warning. A subnet smaller than the cloud allows is still calculated, with `BelowCloudMinimum` and a warning, because the graph reports it as a finding rather than refusing it.

## 4. VLSM never fragments

`New-SubnetPlan` rounds each request up to a power of two and places them largest first, each aligned on its own size. Under that order the blocks pack perfectly, so a plan fits exactly when the sizes add up to no more than the parent; the error can therefore name the shortfall as one number. Requests with the same size keep the order given (`Sort-Object -Stable`).

## 5. Test-SubnetOverlap: Overlaps means identical

Two CIDR blocks either nest or are disjoint; they can never partly overlap. The spec's four relations map to: Overlaps (the same block), Contains, ContainedBy, Disjoint.

## 6. Auto means native when installed

Every observe command picks the native tool when it is installed and the .NET floor otherwise (the spec's rule). One exception in effect: `Invoke-NetworkScan` without nmap calls the TCP floor directly, not `Test-NetworkPort -Tool Auto`, because on Windows Auto would mean Test-NetConnection, which ignores timeouts and takes about 20 seconds per filtered port. `Test-NetworkPort -Tool Auto` on Windows still uses Test-NetConnection; use `-Tool DotNet` for speed.

## 7. ss always runs as ss -tunap

With only `-t` or `-u`, ss drops the Netid column, so the column positions change. The module always asks for both and filters afterwards. Found by the Linux live tests, not the fixtures, which were captured with `-tunap`.

## 8. Cmdlet output as fixtures

The spec's fixture rule (`tests/fixtures/<tool>.<os>.txt`) fits text tools. Windows cmdlets return objects, so their fixtures are the objects' relevant properties as JSON (`Get-NetTCPConnection.windows.json`), with enums as strings. `Get-NetIPConfiguration` nests CIM objects; `Get-NetworkGraphNetIPConfiguration` flattens them first and the fixture was captured through that same function, so the test covers the mapping that live data goes through.

## 9. Fixture scrubbing

Fixtures are real captures. Before saving, the device-specific half of LAN MAC addresses was replaced (the vendor half kept, so lookups still work), and a public address seen in the ARP table was replaced with a documentation address (203.0.113.128). Formats and column alignment are unchanged.

## 10. Neighbours have no .NET floor on Windows

.NET has no API for the ARP and neighbour table. On Linux the floor reads `/proc/net/arp` (a file, not a tool). On Windows `-Tool DotNet` is a terminating error that says so.

## 11. Routes on the .NET floor are derived

.NET has no route table API either. The floor derives what the interface configuration implies: an on-link route per address prefix and a default route per gateway, with no metric, and says so in Source.

## 12. UDP ports

UDP has no handshake. The floor sends one empty datagram: a reply is open, an ICMP port-unreachable is closed, silence is `$null` (unknown). `nc -u -z` reports every UDP port open, so UDP always goes through the floor and Source says so.

## 13. Graph: edge kind values

Property names match TerraformGraph (`From`, `To`, `Kind`), but the kind values are the spec's lower-case hyphenated words, where TerraformGraph uses PascalCase (`Contains`, `InstanceOf`). See docs/graph-shape.md.

## 14. Graph: Findings is a list

TerraformGraph's ResourceGraph has `Findings` as an integer script property. Here `Findings` holds the rows and `FindingCount` the number. Same name, different type; documented in docs/graph-shape.md.

## 15. Graph: which listeners are findings

WildcardListener fires only for TCP sockets listening on 0.0.0.0 or ::. UDP sockets bound to the wildcard address are left out: Windows keeps hundreds of them for ephemeral queries, and they would drown the real listeners.

## 16. Graph: interface subnets

An interface address makes a Subnet node `<prefix>@None`, except loopback, link-local and host (/32, /128) prefixes: fe80::/64 on every interface would merge unrelated links into one node.

## 17. ASN and owner

`Asn` and `Owner` on a cloud address are the cloud's primary network as PeeringDB lists it (8075, 16509, 15169), stored in cloud-ranges.json. They are not the BGP origin of that prefix; the module does no BGP lookup. RDAP reports an ASN only when the registry includes it (ARIN's `arin_originas0_originautnums`, often empty).

## 18. Test-NetworkPort: Auto is the .NET path (2026-10-07)

Supersedes the Test-NetworkPort half of note 6. `Test-NetworkPort -Tool Auto` uses the TcpClient path, not the native tool: Test-NetConnection ignores `-Timeout` and spends about 20 seconds on a filtered port, so a check meant to take `-Timeout` milliseconds took twenty seconds per port. `-Tool Native` still runs Test-NetConnection (Windows) or nc (Linux). `Invoke-NetworkScan` without nmap still calls the batch helper directly, now for a different reason: its `-ThrottleLimit` spans every target and port at once, where Test-NetworkPort batches one target at a time. Its UDP path no longer forces `-Tool DotNet`, since Auto means the same.

## 19. Graph: edge kinds are PascalCase (2026-10-07)

Supersedes note 13. Edge kinds are `Contains`, `RoutesTo`, `HopsTo`, `ConnectsTo`, `OwnedBy`, `ResolvesTo`, `BelongsTo`, matching TerraformGraph, and `Add-NetworkGraphEdge` compares them case-sensitively. The two remaining differences (Findings as a list, the Source node property) are TerraformGraph's to close; see docs/graph-shape.md.

## 20. Fixture scrub, second pass (2026-10-07)

Note 9's scrub missed some values; the rule is now written down in CLAUDE.md and enforced by Pester. Changed: the Hyper-V MACs `00-15-5D-...` in Get-NetNeighbor.windows.json, arp.windows.txt and Get-NetIPConfiguration.windows.json and the container MACs in arp.linux.txt, ip-neigh.linux.json, proc-net-arp.linux.txt and ip-addr.linux.json had their device half replaced with `00-00-nn`; the EUI-64 link-local address `fe80::12b6:76ff:fe..` in Get-NetNeighbor.windows.json, which carried the original device half of `10-b6-76-00-00-04`, now ends `fe00:4`; and the address rdap-arin.json was queried for, the capturing host's external address, is now 203.0.113.7 (the address the test asks RDAP about). The registry's own network (MSFT, 20.33.0.0 to 20.128.255.255) is public data and stays.
