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

## 21. Hops: Responded, AvgMs, and loss that is not loss (0.1.1)

A router that declines to send ICMP Time Exceeded shows `*` in every tool, which 0.1.0 reported as LossPercent 100. When a later hop answered, the path delivered and that is not loss. Every hop parser now returns through `Complete-NetworkGraphHop`, which sets `Responded`, sets LossPercent `$null` for a silent hop followed by one that answered, keeps a real LossPercent where some probes answered, and keeps 100 for silent hops at the end. `RttMs` means per-probe samples only. mtr and pathping report one average per hop, which is `AvgMs` with RttMs empty; for the others AvgMs is the mean of the samples. Rejected: inferring loss from the final hop, which needs both the tool's probe count and its retry behaviour.

## 22. Ids: the PID on a connection, the tool on a hop (0.1.1)

Two sockets sharing an endpoint (SO_REUSEADDR: mDNS 0.0.0.0:5353 held by several processes) were one Connection node with two OwnedBy edges. The Id now ends `/<pid>` when the process is known. A native and a .NET trace of the same target merged into one chain; the Hop Id is now `hop/<target>/<tool>/<n>`, and a Hop row without Tool takes the first word of its Source.

## 23. Native results are checked in one place (0.1.1)

`Invoke-NetworkGraphNative -OkExitCodes` is mandatory, and the runner throws on any other exit code or a timeout, with stderr and the command line. Exit codes that are answers are declared by the caller: ping 1 (no reply), nc 1 (closed), nslookup 1 (no such name), ufw 1 (not root, read as Unknown), firewall-cmd 1 and 252 (not running, or no D-Bus). Commands that loop over targets (ping, nc) turn a failure into a non-terminating error for that target. Rejected: checking in each command, where three of nineteen call sites did.

## 24. Output a parser does not recognise is an error (0.1.1)

Parsers read English. With exit code 0, non-empty output and zero rows, `Assert-NetworkGraphRecognised` throws "output not recognised (non-English locale?); use -Tool DotNet" instead of answering "down" or "nothing". This applies to ping, tracert, pathping, traceroute, arp, nslookup, dig and ss. Exempt: an ss header with no sockets and nslookup's "can't find", which are real empty answers; nc, whose exit code decides and whose text is only read for the port; and ufw and firewall-cmd, whose parsers already return Unknown with the text as the reason. On Linux and macOS, native tools run with LC_ALL=C and LANG=C. On Windows, Auto for Test-NetworkPath and Trace-NetworkPath is the .NET path (see note 18 for Test-NetworkPort): ping.exe, tracert and pathping follow the display language, and .NET's Ping uses the same ICMP API. They still run with `-Tool Native` or `-NativeTool`.

## 25. Firewall: third-party products and ufw.conf (0.1.1)

When every Windows Firewall profile is off, Get-NetworkHost reads root/SecurityCenter2 FirewallProduct. An enabled product (productState state byte 0x10) makes Firewall `ThirdParty`, with its name in FirewallReason and FirewallProducts. On Linux, /etc/ufw/ufw.conf ENABLED= is read first, which needs no root; `ufw status` is the fallback. The platform the observe commands branch on is `$script:NetworkGraphPlatform`, so tests can take another platform's path.

## 26. Every Source is pasteable (0.1.1)

A Source is one of: a command line (a resolvable verb-noun command, or a wrapped native tool's command line); a .NET expression that starts with a full type name and applies its timeout (`.ConnectAsync(...).Wait(ms)`), where notes the wrap rule requires ("no process information") are trailing `#` comments; or a data citation `<file> pulled <date> (<url>)` from `Get-NetworkGraphDataCitation`. Get-ExternalIpAddress gives each answer its own Source, the RDAP request as the Invoke-WebRequest call the private wrapper makes (the wrapper is not exported, so it could not be pasted), and its own Source reruns the command. Subnet nodes carry the `Get-Subnet` command that recalculates them, with the reservation citation as a comment. Graph.Tests "Every Source is pasteable" checks every form, and that `[scriptblock]::Create()` parses it.

## 27. Port latency is per connect (0.1.1)

Each connect's time starts after its own client is built, not at batch start, and a connect that has already finished when ConnectAsync returns is timed then. PowerShell cannot timestamp a task's completion from another thread without compiled code, so the others are timed when WaitAny returns them. Open now means the connect task completed within `-Timeout`, which is what Client.Connected meant. Tests replace the connect with `$script:NetworkGraphTcpConnector`.

## 28. macOS (0.1.1)

The module imports on macOS with one warning that it is untested. Get-NetworkNeighbor says there is no .NET floor there rather than read /proc.

## 29. Fixture scrub, third pass: ISP infrastructure (0.1.1)

Replaced in every fixture: the ISP's resolvers 68.105.28.11, 68.105.28.12 and 68.105.29.11 (now 192.0.2.53 to .55) and resolver name doh.cox.net (now dns.example.net); the first public hops after the gateway, 68.1.0.191 and 184.183.131.9 (now 198.51.100.1 and .2), in tracert and pathping; and a Wi-Fi adapter description naming its device model (now `Wireless Network Adapter`). Module.Tests keeps the literal list as the record. The CGNAT and ISP-internal hops (10.129.232.1, 100.127.77.86) and the Cloudflare hop stay: they are private, shared address space, or a third party.

## 30. The two doors are banners, not a ban (2026-10-07)

Pester "keeps the two doors" now checks only the banners, as in TerraformGraph (its DECISIONS 52): README line 1 is a `>` blockquote linking ONTOLOGY.md, ONTOLOGY.md's first non-blank line is a `>` blockquote and its second links README.md. README may mention or link ONTOLOGY.md again where a reader needs it; the agent story, terminology and facts and opinions still live in ONTOLOGY.md, and the readme and ontology-doc skills say so. Rejected: keeping the ban on `ontolog` after README line 1, which fails a sentence that merely points at ONTOLOGY.md and cannot tell a pointer from duplicated prose; dropping the test, since the banners are what make each door findable from the other. Cost: ontology prose can creep into README.md without a test failing; the readme skill's "Do not add ontology prose" line and review are the only guard.

## 31. Interface Ids: a stable key, not the alias; Source on every edge (0.2.0)

Interface Ids were `<host>/if/<alias>`, and the alias is the one thing about an adapter a user is invited to change (Rename-NetAdapter, `ip link set ... name`): a rename forked the node, and every Route Id that embedded the alias forked with it. The Id is now `<host>/if/<InterfaceKey>` and Route Ids end in the same key.

- Windows: the interface GUID. Get-NetIPConfiguration already reads `NetAdapter.InterfaceGuid`, so the interface path needs no new call. Get-NetRoute, Get-NetNeighbor and arp give only an index, so routes and neighbours look it up in `[System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()` (in process, no launcher): its `Id` is the same GUID, and unlike Get-NetAdapter it includes the loopback pseudo-interface that 127.0.0.0/8 and ::1 route through. The lookup is named in Source.
- Linux: the ifindex. `ip -j addr` carries it; for ip route, ip neigh, arp and /proc/net/arp, which name a device, the lookup reads `/sys/class/net/<dev>/ifindex`, which is the same number. It is boot-scoped (the kernel numbers interfaces as they appear), which graph-shape.md says; there is no more stable identifier that every interface has.
- Rejected: the MAC address. Loopback, tunnels (tun, WireGuard, Wintun) and some virtual adapters have none; randomised and locally administered MACs change by design (Wi-Fi privacy addresses); and two interfaces can share one (bonds, VLAN subinterfaces, the Wi-Fi Direct adapters this host's capture shows with the Wi-Fi adapter's vendor half). It would fork nodes or merge distinct ones, the two failures the key exists to prevent.
- A row with no key (from 0.1.x, or a lookup that found nothing) borrows the key of an Interface row with the same name in the same input, and only then falls back to the alias, with InterfaceKey `$null` so the fallback is visible.

Edges gained `Source` for the same reason nodes have it: an agent that follows an edge should be able to paste the command that asserted it. An edge between nodes from two rows takes the Source of the row whose processing created it (the table in graph-shape.md); this opens a third difference from TerraformGraph, whose edges are exactly From, To, Kind.

Fixtures: Get-NetIPConfiguration.windows.json, Get-NetRoute.windows.json and Get-NetNeighbor.windows.json were recaptured on 2026-10-08 together with the new NetworkInterface.windows.json (the lookup's input), so indexes and GUIDs agree across the four; the 0.1.1 captures predate the GUID and index fields and their indexes no longer match this host. Routes and neighbours are a chosen subset of real rows, as before. Scrubbed per CLAUDE.md: device halves of the MACs (Wi-Fi 04-56-E5 and TAP 00-FF-D1 keep their earlier numbers 10 and 11, the router CC-40-D0 keeps 02, 10-B6-76 keeps 04 also inside its EUI-64 address; new devices take 30 to 33), the ISP resolvers (the same documentation addresses as in 0.1.1), and the two adapter descriptions that name a device model. Beyond the rule, the interface GUIDs were replaced with `{00000000-0000-0000-0000-0000000000nn}`, `nn` the interface index, because a GUID identifies one installation. No renamed-adapter capture was made (renaming needs an administrator and changes the host); the rename test changes the alias of the one real capture in the test itself.

