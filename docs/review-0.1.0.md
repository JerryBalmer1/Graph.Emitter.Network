# NetworkGraph 0.1.0: review

For the architect. Written 2026-10-07 after the 0.1.0 build and the pre-commit cleanup (Apache 2.0, PascalCase edge kinds, Test-NetworkPort Auto on .NET, fixture scrub rule). The reader has seen the build report, not the code. Every item says what is weak, what fixing it costs, and who gains. Section F puts them in order. Each item can be taken or dropped alone.

Numbers below were measured on the Windows 11 build machine (PowerShell 7.6, 1,297 live sockets) unless an item says otherwise. "Verified" means I reproduced it; anything I could not reproduce is marked as such.

## A. What I would not ship as-is

**A1. On non-English Windows the default ping path says a live host is down, and gives no warning.** Test-NetworkPath uses ping.exe whenever it is installed, which is always on Windows. Its parser is English regex. I fed it the German output of a successful ping and got `Reachable False, Received 0, LossPercent 100`, with no error and no warning. tracert, pathping, `arp -a` and nslookup have the same kind of parser: on a localised OS they return zero rows, also silently. The build report said "English only" in passing. It did not say that the default command gives a confident wrong answer outside English locales. On Linux, iputils ping and net-tools arp have message catalogues. I did not verify whether common distros install them, and the module does not set `LC_ALL=C`.
- Fix: (1) On Windows, Auto for Test-NetworkPath and Trace-NetworkPath becomes the .NET floor. `System.Net.NetworkInformation.Ping` calls the same ICMP API as ping.exe and tracert (IcmpSendEcho2), so the native tool adds only locale risk. pathping stays available by name. (2) Any text parser that gets exit code 0, non-empty output and zero rows raises "output not recognised (non-English?); use -Tool DotNet". (3) Invoke-NetworkGraphNative sets `LC_ALL=C` for child processes on Linux.
- Cost: about 4 h and 60 lines, plus tests. No new fixture is needed: (2) is tested with existing fixtures truncated to their header line. A real German capture would need a language pack or a German VM, and we never invent fixtures.
- Value: every user outside an English locale, which is a large part of a Gallery audience. It turns a false "host down" into either a correct answer or a clear error.

**A2. Native exit codes are ignored almost everywhere, so a failed tool looks like an empty network.** Of 19 native call sites, three check ExitCode (curl, nmap, nc) and none checks TimedOut. Verified: `ip` without `-j` (busybox `ip` on Alpine and other minimal images, or iproute2 older than 4.13) writes its error to stderr. Stdout is empty, the parser returns 0 routes, and the user sees no error. A tool killed at its timeout has its partial output parsed as if it were complete.
- Fix: one check in Invoke-NetworkGraphNative, or in a thin wrapper around it: non-zero exit or a timeout throws with stderr and the command line. Each caller declares the exit codes that are meaningful to it (ping exits 1 for "no reply").
- Cost: 2 to 3 h, about 40 lines, one seam test per command.
- Value: Linux container and minimal-image users. Silent blanks become actionable errors, and A1's "not recognised" check builds on this.

**A3. Get-NetworkHost reports the firewall as Disabled on machines whose firewall is on.** Verified on the build machine: all three Windows Firewall profiles are off and Norton Security is the registered, active firewall (`root/SecurityCenter2 FirewallProduct`, productState 331776). Get-NetworkHost says `Firewall: Disabled`. Any third-party firewall (Norton, McAfee, ESET, Sophos) gives the same false alarm. On Linux, `ufw status` needs root, so a normal user always gets Unknown, and nftables-only hosts are never consulted.
- Fix: on Windows client SKUs, also read SecurityCenter2 and report "Windows Firewall off; Norton Security registered" with State `ThirdParty`. On Linux, read `/etc/ufw/ufw.conf` (ENABLED=yes), which needs no root.
- Cost: about 2 h, 30 lines, one fixture per platform.
- Value: anyone who reads Get-NetworkHost as a quick security posture. Today it raises a wrong alarm, and an agent reading the output would act on it.

**A4. `Get-ExternalIpAddress -Rdap` reports a Cidr that does not contain the address, and a test pins that wrong value.** RDAP returns a list of CIDR blocks (`cidr0_cidrs`), and the code takes the first one. In the captured ARIN response the first block is 20.33.0.0/16, but the address the response was captured for lies in 20.64.0.0/10. The test asserts `Cidr -eq '20.33.0.0/16'`. Verified.
- Fix: choose the block that contains the address. The test then queries an address inside the registry's network, because the fixture's own query address is now a documentation address after the scrub.
- Cost: 30 min, 5 lines.
- Value: anyone who uses Cidr to scope a firewall rule or an allow list. A wrong prefix there is a real error.

**A5. ConvertTo-NetworkGraph drops every row that crossed a process boundary.** Verified: rows returned by `Invoke-Command`, a job, or `pwsh -Command { }` carry the type name `Deserialized.NetworkGraph.Connection`. The graph matches exact type names, so it skipped all 88 rows with a warning and produced 0 nodes. "Graph a remote server's connections" is therefore impossible today, although the observe commands work remotely.
- Fix: accept an optional `Deserialized.` prefix when matching types.
- Cost: 15 min, 2 lines plus one test.
- Value: anyone graphing a host other than the one they are sitting at, which is most server work. Very high value for the cost.

**A6. A hop with LossPercent 100 usually has no loss.** A router that does not send ICMP Time Exceeded (filtered or rate-limited) shows `Ip $null, LossPercent 100`, while every later hop shows 0 and the target answers. The field name invites the classic misreading "packet loss at hop 4". A renderer will paint that node red, and an agent will report it as loss.
- Fix: add `Responded` (bool), and set LossPercent `$null` when no probe to that hop got an answer but a later hop did. Document both. This changes the Hop node contract, which is cheaper before the Gallery than after.
- Cost: 1 to 2 h: parsers, graph doc and tests.
- Value: everyone who reads a trace, and especially agents and junior engineers.

**A7. Source does not always let someone rerun the command.** This is the module's stated promise, and it holds for native tools. It fails here:
- .NET floor Sources are pseudo-code. `[IPGlobalProperties]::GetIPGlobalProperties()...` and `[NetworkInterface]::GetAllNetworkInterfaces()` lack their namespace, so pasting them fails with "type not found". The TCP Source `[System.Net.Sockets.TcpClient]::new().ConnectAsync('ip', port), timeout 2000` returns a Task and applies no timeout. The trace Source ends in prose ("for ttl 1..30 x 3"). The UDP Source says `Send(empty)`.
- Get-ExternalIpAddress joins four or five commands with `; `, and one of them is `RDAP <url>`, which is not a command.
- Test-IPAddress Source is the RFC for special-use rows and `$null` for public and cloud addresses. A cloud verdict cites no file, pulled date or source URL.
- Graph nodes: Subnet Source is `Get-Subnet` or `New-SubnetPlan` without arguments, and the Cloud node says `cloud-ranges.json.gz` without a pulled date.
- Fix: every .NET Source becomes a pasteable one-liner (full type names, `.Wait(timeout)`). Any verdict derived from data cites `<file> pulled <date> (<source url>)`.
- Cost: 2 to 3 h, about 40 lines. The tests already compare Source strings.
- Value: reviewers and agents auditing output. It is the property that makes this module different from the cmdlets it wraps.

**A8. Connection and Hop Ids collide.** A Connection Id is protocol plus local and remote endpoint. Two sockets that share an endpoint (SO_REUSEADDR: on this machine msedge and ChatGPT both hold UDP 0.0.0.0:5353) merge into one node that carries the first ProcessId, while both OwnedBy edges remain. Checklist 1.6 shows it: 407 Connection nodes and 408 OwnedBy edges. Hop Ids are `hop/<target>/<n>`, so tracing the same target twice (native and .NET, exactly as checklist 1.5 does) merges the two chains.
- Fix: add the PID to the Connection Id when one is present, and a trace discriminator (tool, or a sequence number) to the Hop Id.
- Cost: 1 h plus the contract doc.
- Value: graph correctness. Collisions are rare, but when they happen the graph shows the wrong owner.

**A9. MAC vendor lookup is wrong for IEEE's small blocks, and IsRandomized overclaims.** oui.json holds only MA-L (24-bit) assignments. A MAC in an MA-M or MA-S block (for example 00-1B-C5 or 00-50-C2) gets Vendor `IEEE Registration Authority`, which is a wrong answer shaped like a right one. Those blocks are exactly where IoT and industrial vendors sit. Separately, `IsRandomized` is set equal to `IsLocallyAdministered`, so every VM, Docker, Hyper-V and admin-assigned MAC is labelled "randomized".
- Fix: harvest mam.csv and oas.csv from the same IEEE site and match longest first (36, 28, then 24 bits). Drop IsRandomized, or document it as "locally administered, often randomized".
- Cost: 2 to 3 h, a harvester change, and an UpdateData run (network).
- Value: anyone identifying unknown devices on a LAN, which is a common first use of Get-NetworkNeighbor.

**A10. RDAP has gaps beyond A4.**
- Owner is the first top-level entity with role `registrant`. Nested entities are not walked, so for RIRs that nest the organisation Owner falls back to the network name.
- Asn comes only from ARIN's `arin_originas0` extension, which is empty even in our own fixture.
- Every RDAP test uses the ARIN fixture. The APNIC fallback test serves ARIN JSON from an APNIC URL, so no RIPE, APNIC, LACNIC or AFRINIC response has ever been parsed.
- The default path depends on rdap.org, a single third-party redirector. The fallback only runs when rdap.org throws. Nothing is cached and there is no 429 handling.
- Fix: capture one real response per RIR (Live, then scrub) and walk nested entities.
- Cost: about 3 h, needs network for the captures.
- Value: users whose address is outside North America, which is most of the world.

**A11. Routes on the .NET floor are invented, and Linux has a real table to read instead.** With no `ip` on Linux, Get-NetworkRoute returns one on-link route per address and one default route per gateway. It has no static routes, no VPN split-tunnel routes and no metrics. Source says "derived", but the rows look like routes, and Get-NetworkHost's DefaultGateway and the graph treat them as routes. Linux exposes the kernel table as files (`/proc/net/route`, `/proc/net/ipv6_route`), the same precedent the module already uses for `/proc/net/arp`. Windows never reaches this floor in Auto, because Get-NetRoute is always present.
- Fix: a /proc parser for the Linux floor. Keep the derived floor only where no table exists, and mark those rows `Derived $true`.
- Cost: 2 to 3 h plus a Linux fixture captured in a container.
- Value: Linux minimal images (busybox `ip`, see A2). The frequency is low, but when it happens the output misleads.

**A12. Some features work only because a native tool happens to be installed.** Most of these fail loudly, which is fine:
- Resolve-NetworkName `-Server` and record types beyond A, AAAA and PTR need dig or Resolve-DnsName.
- Process names in Get-NetworkConnection need Get-NetTCPConnection or ss.
- Per-hop loss needs pathping or mtr.
- Get-NetworkNeighbor on Windows needs Get-NetNeighbor.

Two fail silently: Linux `ip -j`, which needs iproute2 4.13 or later (see A2), and the firewall state (see A3). The README's tool table should say, per command, what you lose on the floor.
- Cost: 30 min of docs once A2 and A3 are fixed.

**A13. macOS runs the Linux code paths, although the docs only say it is untested.** On macOS, `$IsWindows` is false, so Auto runs the Linux candidates. `ss` and `ip` are absent, so the module drops to .NET. That is fine, except Get-NetworkNeighbor: its floor reads `/proc/net/arp` and throws FileNotFound, and its `arp -a` fallback runs a Linux regex over BSD output.
- Fix: one warning at import on macOS, and a `-NoDotNet` reason for Get-NetworkNeighbor there.
- Cost: 15 min.
- Value: honesty. macOS users get "unsupported" instead of a stack trace.

**A14. Test-NetworkPort LatencyMs is measured from batch start.** The stopwatch starts before the batch's clients are constructed, so later ports include the construction time of earlier ones. The first call in a process also includes JIT time: checklist 1.8 shows 28.6 ms to a loopback listener.
- Fix: record the start time per connect.
- Cost: 30 min.
- Value: anyone comparing latency across ports. Small, but the number is labelled latency, so it should be latency.

**A15. The fixtures still identify the ISP and region.** The scrub rule now covers MACs, the host's own public address and identifying host names. It deliberately leaves other parties' addresses, and together these narrow the capturing household to one ISP and area: Cox resolvers 68.105.28.11 and 68.105.28.12, `doh.cox.net`, Cox first public hops 68.1.0.191 and 184.183.131.9 in tracert and pathping, and adapter names that hint at the laptop model.
- Fix: decide whether the rule extends to "first-party ISP infrastructure"; if so, replace those values with documentation addresses.
- Cost: about 1 h, plus a rule line and a test.
- Value: the repo owner's privacy, once the repo is public.

## B. What I would do better if I did it again

**B1. One adapter table instead of ten hand-written tool switches.** Each observe command repeats the same skeleton: an `$IsWindows` candidate list (9 public files), Resolve-NetworkGraphTool, a `switch` per tool, `Add-Member Source ... -PassThru` (20 sites), and in most cases no exit-code handling. A1 and A2 would each have been one change in one place.
- Better choice: a data table of adapters `{ Command, Platform, Tool, Arguments, Parser, OkExitCodes }` and one runner. The runner owns `LC_ALL=C`, exit and timeout checks, "parsed nothing" detection and Source stamping.
- Cost now: 1 to 2 days, touching every observe command. Risk is moderate, but the fixture and seam tests cover both the parsers and the commands.
- Value: every future tool or command becomes a table row plus a parser, and behaviour stays consistent across commands.

**B2. 62 private functions for 23 public is a signal, but mostly of B1, not of the file layout.**
- 25 tool or format mappers. Eight of them are 14-to-21-line mappers over Windows cmdlet objects, which exist so those objects can be JSON fixtures (design note 8).
- 5 row builders, 5 data-plumbing helpers, 4 harvesters, 2 graph helpers.
- About 20 small utilities, some very thin: ConvertTo-NetworkGraphMac is 9 lines, HopText 12, Resolve-NetworkGraphTarget 17.

The one-function-per-file rule makes each of these a file. D shows that small files are cheap to read, so the count is not itself the cost. The cost is that the shared shape (tool, run, check, parse, stamp) was never extracted.
- Better choice: do B1, fold the eight cmdlet mappers into the row builders, and let the count fall to about 45. Do not restructure the layout for its own sake.

**B3. Regex is used where a structured or authoritative alternative exists.**
- Windows ping.exe and tracert are parsed as text, although .NET Ping is the same ICMP API (see A1).
- `nc -z` output is parsed, although the exit code is authoritative and the module runs one port per call.
- The Linux `arp -a` fallback sits ahead of `/proc/net/arp`, which is better and is already the floor.
- `ufw status` (needs root) is parsed instead of `/etc/ufw/ufw.conf`.
- The Linux route floor derives routes instead of reading `/proc/net/route` (see A11).

Regex is justified for pathping, traceroute, ss and dig, which have no structured output that PowerShell can read without a new parser.
- Cost: covered by A1, A3 and A11, plus about 1 h to drop the Linux arp and nc parsers.

**B4. Importing from `src` costs about 1 s; the assembled module costs 0.16 s.** `src` dot-sources 85 files (62 private, 23 public) one by one. `Invoke-Build Assemble` already produces a single-file module, but nothing makes it the published artifact.
- Better choice: publish only `dist/`, add a Publish task that assembles first, and add one Pester test that imports `dist`.
- Cost: about 1 h.
- Value: about 0.85 s saved on every import for every user, with no change to the development layout.

**B5. The first cloud lookup costs 1.1 to 1.3 s.** cloud-ranges.json.gz (516 KB compressed) is decompressed and loaded into a hashtable keyed by prefix. Every session that runs `Get-NetworkConnection -Resolve` or ConvertTo-NetworkGraph pays this once. Later lookups take about 35 ms.
- Better choice: a line-oriented format (`cidr<TAB>cloud<TAB>service<TAB>region`, split as it is read), or numeric start and end ranges sorted for binary search. Bump formatVersion.
- Cost: 3 to 4 h, in the harvester and the reader.
- Value: moderate. It improves the interactive feel of the commands people run most.

**B6. Per-row function overhead makes the observe commands slow.** Measured with the assembled module (not `src`), on 1,297 sockets:

| Step | Time |
|---|---|
| Get-NetworkConnection | 5.6 s |
| Get-NetworkHost | 8.1 s |
| First ConvertTo-NetworkGraph | 5.7 s |

netstat answers instantly. Each row passes through a row-builder function, two BigInteger address conversions done only to unmap IPv4-mapped addresses, Add-Member and a TypeNames insert. Find-NetworkGraphSpecialUse does a linear scan with `Where-Object | Sort-Object` for every address.
- Better choice: build `[pscustomobject]` literals in the mappers, unmap with a string check, and index special-use prefixes once.
- Cost: 3 to 4 h.
- Value: high for interactive use. Engineers call Get-NetworkConnection repeatedly.

**B7. Duplication that has already cost something.**
- The NetworkGraph.Port row is built in three places.
- The UDP probe is inline in Test-NetworkPort, while TCP has a helper.
- `ThrowTerminatingError([ErrorRecord]::new(...))` boilerplate appears 14 times.
- The TCP state vocabulary lives in two places: the `-State` ValidateSet and the value map in ConvertTo-NetworkGraphTcpState. They have already drifted: Windows emits `DeleteTCB`, the ValidateSet lacks it, and so you cannot filter on it (see D2).
- Better choice: New-NetworkGraphPortRow, a New-NetworkGraphError helper, and one `$script:NetworkGraphTcpStates` list that feeds both the completer and the map.
- Cost: about 3 h.

**B8. The hop shape is built six ways and RttMs means two things.** tracert, pathping, traceroute and the .NET trace report per-probe samples. mtr reports one average, and pathping reports one RTT. All of these land in the same RttMs field, and Trace-NetworkPath then re-wraps every row.
- Better choice: RttMs always means samples; add AvgMs, and put mtr's and pathping's numbers there.
- Cost: 1 to 2 h. Pair it with A6, since both touch the Hop contract.

**B9. "Native first" was applied as a rule where it should have been a judgement per command.** Test-NetworkPort now breaks it, ping and tracert on Windows should too (A1), and the Linux `arp` and `nc` fallbacks are worse than the floor (B3).
- Better choice: one table in the README stating, per command, what Auto picks and why, with the reason in each function's comment.
- Cost: 30 min of docs once A1 lands.

## C. What a network engineer will hit in the first hour

These are not the README's "Not here yet" list. Each is something I expected while building or testing and found missing.

**C1. "Which route will traffic to X take?"** Get-NetworkRoute lists the table, but nothing does the longest-prefix match. The OS answers this (Find-NetRoute on Windows, `ip route get` on Linux), and the subnet math is already in the module to do it offline over the table. This is the most common routing question there is.
- Cost: 2 to 3 h.
- Value: high.

**C2. Fitting new subnets into an existing VNet.** New-SubnetPlan plans from an empty parent and has no `-Existing` or `-Exclude`. Cloud engineers almost always have allocations already. Design note 4's "never fragments" property no longer holds once there are holes, so the packer needs a free-list.
- Cost: 3 to 4 h.
- Value: high. It is the most common cloud subnet question after "how many usable addresses".

**C3. Summarise and convert ranges.** Two everyday ACL and route-summary tasks are missing: collapsing 10.0.0.0/24 and 10.0.1.0/24 into 10.0.0.0/23, and turning "10.0.0.0 to 10.0.5.255" into a list of CIDRs.
- Cost: about 2 h on the existing BigInteger path.
- Value: medium to high.

**C4. "What is alive on this subnet?"** Invoke-NetworkScan without nmap connects to six TCP ports per address, and there is no ICMP sweep. Host discovery should be a parallel .NET Ping sweep followed by a read of the neighbour table, which shows hosts that drop ICMP but answered ARP.
- Cost: 2 to 3 h. It is inside the wrap rule: no evasion, and nothing beyond what ping does.
- Value: high. It is usually the first thing someone types.

**C5. TLS on a port.** Engineers want to know which certificate a port serves, its subject, SANs, issuer and expiry, and the protocol version. This is pure .NET (SslStream), and Test-NetworkPort already holds the socket.
- Cost: 2 to 3 h.
- Value: high. Expired or wrong certificates are a daily outage cause.

**C6. Path MTU.** Test-NetworkPath has no `-Size` or `-DontFragment`. PingOptions supports both. This is a VPN and tunnel troubleshooting staple.
- Cost: about 1 h.
- Value: medium.

**C7. Interface facts.** Get-NetworkInterface has no MTU, link speed, DHCP state, DHCP server or lease, and no Wi-Fi SSID or signal. "Is this NIC at 1 Gbps, and is it on DHCP?" is an hour-one question. The sources are Get-NetAdapter and Get-NetIPInterface on Windows, and `ip -j link` plus `/sys/class/net/*/speed` on Linux.
- Cost: 2 to 3 h.
- Value: medium.

**C8. Proxy.** Get-ExternalIpAddress mentions proxies, but nothing reports the effective proxy: WinHTTP, the `HTTP(S)_PROXY` variables, or a PAC file. Corporate users hit this the first time Get-ExternalIpAddress fails.
- Cost: 1 to 2 h.
- Value: medium.

**C9. Elevation hints.** Several outputs lose data without elevation: `ss -p` without root shows no process for other users' sockets, ufw needs root, and `nmap -sU` needs Administrator. Rows do not say "not elevated: N rows lack a process", so a partial answer looks complete.
- Cost: about 1 h.
- Value: medium.

**C10. DNS timing and comparison.** Resolve-NetworkName reports no query time and cannot ask several servers in one call. "Is my resolver slow or wrong compared to 1.1.1.1?" is a common first question.
- Cost: 1 to 2 h.
- Value: medium.

## D. Three agent tasks, with lines read

I ran each task as an agent would: grep first, then read only the ranges needed to make the change correctly, including the tests, docs and checklist the rules require. I did not make the changes.

**D1. Change the RDAP endpoint** (for example, replace rdap.org with another redirector). Done when the URL, the docs and the tests agree and the hand-written data file's `pulled` date is updated.

| File | Lines | Read |
|---|---|---|
| `grep -rin rdap src tests docs README.md` output | | 40 |
| src/Graph.Emitter.Network/data/ip-sources.json (the URL lives here) | 1-24 | 24 |
| src/Graph.Emitter.Network/Private/Get-NetworkGraphRdap.ps1 (the `{ip}` template, the fallback trigger) | 1-37 | 37 |
| src/Graph.Emitter.Network/Public/Get-ExternalIpAddress.ps1 (help names rdap.org) | 6-19 | 14 |
| tests/Get-ExternalIpAddress.Tests.ps1 (mocked URLs) | 40-64 | 25 |
| CLAUDE.md, "Data" (hand-written file: re-read the sources, update `pulled`) | | 8 |
| **Total** | 5 files and a grep | **148** |

**D2. Add a State value to Get-NetworkConnection** (`DeleteTcb`, the one Windows TCP state the ValidateSet lacks).

| File | Lines | Read |
|---|---|---|
| src/Graph.Emitter.Network/Public/Get-NetworkConnection.ps1 (help, ValidateSet, three tool branches, filter) | 1-135 | 135 |
| src/Graph.Emitter.Network/Private/ConvertFrom-NetworkGraphNetTcpConnection.ps1 (passes the Windows enum through as text) | 1-21 | 21 |
| src/Graph.Emitter.Network/Private/ConvertTo-NetworkGraphTcpState.ps1 (the ss map: is there an equivalent?) | 1-17 | 17 |
| src/Graph.Emitter.Network/Private/New-NetworkGraphConnectionRow.ps1 (the no-peer rule keys on State) | 1-30 | 30 |
| `grep -n State` over the graph and tests | | 15 |
| tests/Get-NetworkConnection.Tests.ps1 (the -State filter test) | 55-70 | 16 |
| tests/Module.Tests.ps1 (the -State completion test) | 98-104 | 7 |
| manual-check-list.md (rules header and item 1.4; a ValidateSet change needs a checklist item) | 1-8, 85-101 | 25 |
| CLAUDE.md, "Manual check list" | | 3 |
| **Total** | 8 files and a grep | **269** |

**D3. Find why a Hop row has LossPercent 100.**

| File | Lines | Read |
|---|---|---|
| src/Graph.Emitter.Network/Public/Trace-NetworkPath.ps1 (the help states the answer at line 12; lines 68-108 map tool to parser) | 1-13, 68-108 | 54 |
| src/Graph.Emitter.Network/Private/ConvertFrom-NetworkGraphTracertOutput.ps1 (`*` counts as lost) | 1-32 | 32 |
| src/Graph.Emitter.Network/Private/ConvertFrom-NetworkGraphHopText.ps1 (`Request timed out.` gives Ip `$null`) | 1-12 | 12 |
| tests/fixtures/tracert.windows.txt (hop 4: `* * * Request timed out.`) | 1-12 | 12 |
| tests/Trace-NetworkPath.Tests.ps1 (pins `LossPercent 100`) | 10-20 | 11 |
| **Total for Windows (tracert)** | 5 files | **121** |
| Also mtr, traceroute and the .NET trace, to answer for every tool | +3 files | +117, giving 238 |

**Compared with the TerraformGraph audit (187 / 1,349 / 218):** NetworkGraph comes in at 148 / 269 / 121 (238 for all tools). I have not seen that audit's task list, so this is a comparison of three typical maintenance tasks, not the same three tasks. All three were under 300 lines here. Nothing approached 1,349.

What the per-file layout bought:
- The file name answers "where": `grep` for a tool name lands on ConvertFrom-NetworkGraph<Tool>Output.
- Reading a whole file is cheap: the median Private file is about 25 lines, so the agent never pages through a monolith.
- The worst case is bounded by the number of files the change touches, not by the size of one big file.

What it did not buy:
- D2 needed 8 files. The state vocabulary is spread over a ValidateSet, three tool mappers, a row builder, two test files and the checklist. Small files do not help when one concept is defined in several places (see B7).
- D1 was dominated by grep output and tests, not code.
- D3's fastest path was the help text: the answer was on line 12 of the public function. Documentation that states behaviour saved more than the layout did. That argues for keeping comments that say what a value means (E7), not for more files.

## E. What was good and should be kept exactly as it is

**E1. The two seams.** Invoke-NetworkGraphNative is the only process launcher, and Invoke-NetworkGraphWebRequest is the only HTTP call and is HTTPS-only. Each has a test hook. No shell is involved, arguments go in as an array, and a timeout kills the whole process tree. This is why 232 tests run with no tool and no network. Do not add a second launcher, even "just for one tool".

**E2. `Source` on every row, and the Auto, Native and DotNet switch with errors that name the fix.** Messages like "no native tool found... Install one, or run X -Tool DotNet" and "has no .NET floor here" are the best user-facing part of the module. A7 extends Source; nothing should weaken it.

**E3. Real fixtures, never invented, now enforced against leaking.** The scrub tests fail on the 0.1.0 fixtures and pass on the scrubbed ones. Keep the rule that a parser change starts with a real capture.

**E4. One BigInteger path for IPv4 and IPv6** (design note 1). Every subnet function is version-agnostic as a result. B6 removes BigInteger from display-only paths. Keep it in the math.

**E5. Data with provenance.** Every file carries `sources`, `pulled` and `maxAgeDays`. The user cache wins over the bundled copy, and harvested data reaches `src` only through `Invoke-Build UpdateData`, with CheckData naming the fix command. Cloud reservations are data applied per IP version (design note 3).

**E6. The graph contract is tested against the document.** Pester parses docs/graph-shape.md and compares it with real nodes, and Add-NetworkGraphNode refuses unknown properties. The no-`System.Array`-member naming rule prevents a whole class of PowerShell bugs. Edge kinds are now checked case-sensitively against the doc table.

**E7. Comments that say what a value means and why.** Examples: the ss Netid note (design note 7), UDP's three-state Open, "Overlaps means identical" (note 5), and "VLSM never fragments" (note 4). D3 was answered from a help line. Design notes record what was rejected, and they are append-only.

**E8. Get-ExternalIpAddress asks several endpoints and reports `Agreed`.** A split tunnel or proxy shows up as disagreement instead of a single confident address.

**E9. The wrap rule.** No binaries, and nmap runs only with `-oX - -n -Pn -p`, enforced by tests. This is what makes the module safe to install on a locked-down machine and to hand to an agent.

## F. Recommended order

Each item is marked **do now** (0.1.1), **before Gallery** (0.2.0, before the first Publish-Module), or **never**, with the reason. Hours are mine and include tests.

### 0.1.1: do now (about 3 days in total)

| # | Item | Cost | Why now | Status |
|---|---|---|---|---|
| 1 | A5: graph accepts `Deserialized.*` rows | 15 min | Two lines, and it unblocks remote use | done 0.1.1 |
| 2 | A4: RDAP Cidr must contain the address | 30 min | A test currently pins a wrong answer | done 0.1.1 |
| 3 | A2: exit codes and timeouts checked in one place | 2-3 h | Removes silent empty results; A1 builds on it | done 0.1.1 |
| 4 | A1: Windows ping and tracert Auto on .NET, "not recognised" error, `LC_ALL=C` | 4 h | Today the default command gives a confident wrong answer outside English locales | done 0.1.1 |
| 5 | A3: third-party firewall and non-root ufw | 2 h | Today it raises a false "firewall off" alarm | done 0.1.1 |
| 6 | A6 and B8: hop `Responded`, LossPercent `$null` for non-responders, AvgMs | 2-3 h | Hop contract change; cheaper before anyone depends on it | done 0.1.1 |
| 7 | A8: Ids include PID and a trace discriminator | 1 h | Contract change; same reason | done 0.1.1 |
| 8 | A7: pasteable .NET Sources; data verdicts cite file, date and URL | 2-3 h | The module's core promise | done 0.1.1 |
| 9 | A14: LatencyMs measured per connect | 30 min | A labelled number that is wrong | done 0.1.1 |
| 10 | A13: macOS warning; no /proc read on macOS | 15 min | Replaces a stack trace with "unsupported" | done 0.1.1 |
| 11 | A15: decide on ISP-identifying fixture values | 1 h | Do before the repo is public; after that it cannot be taken back | done 0.1.1 |

### 0.2.0: before Gallery

| # | Item | Cost | Why before Gallery |
|---|---|---|---|
| 12 | B4: publish the assembled module only, add a Publish task and a dist import test | 1 h | Every installed user pays the 1 s import otherwise |
| 13 | B6: per-row overhead (5.6 s becomes well under 1 s) | 3-4 h | The first impression of the most-used command |
| 14 | B5: cloud-range format for a fast first load | 3-4 h | Same; bump formatVersion while there are no users |
| 15 | A9: MA-M and MA-S vendor data; fix or drop IsRandomized | 2-3 h + UpdateData | A wrong vendor shaped like a right one |
| 16 | A10: one real RDAP fixture per RIR; walk nested entities | 3 h, network for captures | Most users are not on ARIN |
| 17 | A11 and B3: Linux `/proc/net/route` floor; drop the Linux arp and nc parsers; ufw.conf | 3-4 h | Real data instead of invented routes |
| 18 | B1: adapter table (then B7 and B9 fall out of it) | 1-2 days | Do it before C1, C4 and C7 add more tools, or each repeats the skeleton |
| 19 | C1: route lookup for a destination | 2-3 h | The most common routing question |
| 20 | C2: subnet plan with existing allocations | 3-4 h | The most common cloud subnet question |
| 21 | C5: TLS certificate on a port | 2-3 h | Daily outage cause; pure .NET |
| 22 | C4: host discovery (ping sweep plus neighbour table) | 2-3 h | Usually the first thing typed |
| 23 | C3: summarise and range-to-CIDR | 2 h | Cheap on the existing math |
| 24 | A12: per-command "what you lose on the floor" in the README | 30 min | Docs, after A2 and A3 |
| 25 | C6 to C10: MTU, interface facts, proxy, elevation hints, DNS timing | 1-3 h each | Take them by demand. None blocks the Gallery, so they can slip to 0.3 |

### Do never

| Item | Why never |
|---|---|
| Restructure the one-function-per-file layout (B2 taken literally) | D shows small files are cheap to read. The private count falls naturally with B1 and the cmdlet-mapper fold. |
| Make Test-NetworkPort Auto native again | Test-NetConnection's ignored timeout is a property of the cmdlet, not a bug that will be fixed. |
| BGP or origin-ASN lookups | A host cannot see BGP. It would mean a third-party API presented as observation, which breaks what Source means. |
| Any extra nmap flag (scripts, `-sV`, `-O`, timing) | The wrap rule, and what makes the module safe to hand to an agent. |
| Parse `dig +yaml` | It needs a YAML parser the module does not have. dig's text output is stable and already pinned by a fixture. |
| Claim macOS support without a macOS test box | Untested should stay labelled untested. A13 makes it fail cleanly instead. |
| Windows PowerShell 5.1 | The ternary and null-coalescing syntax throughout, and `ProcessStartInfo.ArgumentList`, would all have to go, for a shrinking audience. |
