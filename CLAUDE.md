# Graph.Emitter.Network

PowerShell 7.4+ module: subnet math with cloud reservations, auditable wrappers over the network tools already installed, and a graph of what a host can see. Pure PowerShell: no Go, no C#, no DLL, no bundled binaries of any kind.

Requires PowerShell 7.4+, Pester 6.1.0+, InvokeBuild. PSScriptAnalyzer for `Invoke-Build Analyze`.

## Working rules

- Agents edit and stage only. No commit, push, branch, tag or release; Jerry does those.
- Keep changes scoped. No drive-by refactors.
- Run Pester in a fresh process, never in the shell that imported the module: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -CI"` (or `Invoke-Build`, which does the same).
- Every change to an exported function, parameter, parameter set, default, ValidateSet, default view or documented example updates `manual-check-list.md` in the same task (see "Manual check list").
- Any exported-function change also updates `ONTOLOGY.md` and `README.md` in the same task, as in TerraformGraph: the three files land with the code, never in a follow-up. The repo skills `manual-check-list`, `ontology-doc` and `readme` (`.claude/skills/`) say exactly which changes touch each file and how; if one of them has nothing to change, say so in the report. Pester "keeps the two doors: README's first line points to ONTOLOGY.md and ONTOLOGY.md links back first" and "resolves every term in ONTOLOGY.md's terminology table to an exported command, a typed object property or a data file" enforce the doors.
- Every data file carries a top-level `sources` array of `{ url, title, pulled }`; no data without a source URL.

## Naming

Node types never have a property named `Address`, `Count`, `Length`, or any other member of `System.Array` (member access on an array of nodes would hit the array's own member); use a qualified name (`Ip`, `InterfaceName`, `OpenPorts`). Pester "has no node property named Address, Count, Length or another System.Array member" enforces it against docs/graph-shape.md. Row objects from observe commands follow the same rule.

## Layout

```
.build.ps1                       Invoke-Build: Test (default), Analyze, Assemble, UpdateData, CheckData
.claude/skills/networkgraph/     repo-only agent skill (working in this repo; not shipped)
.claude/skills/manual-check-list, ontology-doc, readme   repo-only skills keeping the three files below in step with the code (ported from TerraformGraph)
.claude/skills/graph-node, run-report, git-guard   read-only here: copied unchanged from Graph (C:\__Code\Graph\.claude\skills\<name>); never edit them in this repo. tests/CopiedSkills.Tests.ps1 checks each one's version: and full text against Graph's committed copy, and git-guard's exit codes
.claude/settings.json            git-guard's PreToolUse hook: refuses commit, push and tag from an agent's Bash or PowerShell call
README.md                        sysadmin door; README line 1 is a banner linking ONTOLOGY.md; further mentions are allowed; Pester checks only the two banners (skill readme)
ONTOLOGY.md                      agent door; banner, then backlink to README (skill ontology-doc)
docs/graph-shape.md              node and edge contract, and where it came from (TerraformGraph)
docs/design.md                   design notes and judgement calls
src/Graph.Emitter.Network/
  Graph.Emitter.Network.psd1     FunctionsToExport is the export list, grouped by the three groups
  Graph.Emitter.Network.psm1     module-scope state, type data and wiring only; dot-sources Private/ then Public/
  Public/                        one exported function per file, Verb-Noun.ps1
  Private/                       one helper per file, named for its function
  data/                          json data files, each with a top-level sources array
  skills/networkgraph/SKILL.md   shipped skill (same folder convention as TerraformGraph)
tests/                           Pester: one file per Public function, plus Data, Graph and Module
tests/fixtures/                  real tool output, <tool>.<os>.txt (or .json / .xml when the tool emits that)
manual-check-list.md             paste-and-verify checks; append-only numbered items
```

One function per file in both folders; Pester "every Public file exports exactly its function name", "every Private file defines exactly one function named for the file" and "psd1 exports match Public/" enforce it. A new public function needs its file, its psd1 entry (in its group), a test file `tests/<Verb-Noun>.Tests.ps1` and checklist items.

## The three groups, and why

They age at different rates, and that is the cost-of-change seam; keep them visibly separate by noun.

1. **Calculate** (`Subnet*`, `SubnetMask`, `IPAddress`, `MacAddressVendor` nouns): offline, deterministic, no network, no shelling out. BigInteger arithmetic over the address bytes so IPv4 and IPv6 share one path (`ConvertTo-NetworkGraphIpValue`, `Resolve-NetworkGraphPrefix`). Changes when a cloud changes its rules or a registry adds a row, which is a data change, not a code change.
2. **Observe** (`Network*` and `ExternalIpAddress` nouns): wraps what is installed. Changes when an OS or a tool changes its output; the fixture tests are the early warning.
3. **Graph and data** (`NetworkGraph*` nouns): `ConvertTo-NetworkGraph` and the data commands. The graph contract is docs/graph-shape.md; the data refreshes weekly (cloud ranges) to yearly.

## Wrap rule

Wrap installed tools, never ship a binary, never add anything whose purpose is evading a control. Concretely:

- No executable, DLL, compiled C#/Add-Type, or downloaded tool in the repo or the module. Pester "ships no binaries" fails on one.
- `Invoke-NetworkScan` runs nmap only if it is on PATH, with `-oX - -n -Pn -p` and nothing else: no scripts, no version or OS detection, no timing or evasion flags. Do not add them.
- Every observe command: native tool when present, a .NET floor when not, `-Tool Auto|Native|DotNet` (ValidateSet) to force one; a command with no floor on a platform says so in its terminating error (Get-NetworkNeighbor on Windows).
- Every row has `Source`: the tool and exact command line (or .NET call) that produced it. Floors that lack a field say so in Source ("no process information").
- Native commands go through `Invoke-NetworkGraphNative` (the only process launcher; tests replace `$script:NetworkGraphNativeInvoker`) and HTTP through `Invoke-NetworkGraphWebRequest` (HTTPS only; tests replace `$script:NetworkGraphWebInvoker`).
- Parse structured output where the tool offers it (`ip -j`, `mtr --json`, `nmap -oX`, cmdlet objects). Regex only as the last resort, and every regex parser is pinned by a fixture test per platform. Fixtures are real output captured from the tool (`tests/fixtures/<tool>.<os>.txt`), never invented, and scrubbed by the fixture scrub rule below. CI never calls a tool: tests that touch the real network or tools are tagged `Live` and skip unless `NETWORKGRAPH_LIVE` is set (`$env:NETWORKGRAPH_LIVE = 1; Invoke-Pester -Path .\tests -TagFilter Live`).
- Windows and Linux are supported; macOS is untested and docs say so.

## Fixture scrub rule

A fixture captured from a real host is scrubbed before it is saved, without changing its format (column alignment, JSON shape, compression of IPv6 addresses):

- Every LAN MAC keeps its vendor half (the first three bytes) and has its device half replaced with `00-00-nn` (`00:00:nn`), `nn` a sequence number so distinct devices stay distinct. That includes MACs embedded in EUI-64 IPv6 addresses (`...ff:fe..`). Broadcast, multicast and all-zero MACs name no device and stay.
- Every public IP that belongs to the capturing host (its external address, its own global IPv6 addresses, and the address an RDAP or similar lookup was made for) is replaced with a documentation address: 192.0.2.0/24, 198.51.100.0/24 or 203.0.113.0/24 (RFC 5737), 2001:db8::/32 (RFC 3849). Addresses of other parties (1.1.1.1, a remote peer, a registry's own network) stay.
- Host names that identify a person or a site (a computer name, a user name, a home or office domain) are replaced with neutral ones (`testhost`, `example.com`).
- First-party ISP infrastructure is replaced too, because together it narrows a capture to one ISP and area: the resolver addresses and resolver host names the host was given (with documentation addresses and `dns.example.net`), the first public hops after the gateway in a trace (with documentation addresses), and adapter names that identify a device model (with a generic name such as `Wireless Network Adapter`). Third parties stay (1.1.1.1, a CDN hop, a remote peer).

Say what was scrubbed in docs/design.md. Pester "no fixture file contains the capturing host's external address (read from rdap-arin.json)" and "no fixture MAC has a device half other than 00-00-nn, in MAC form or inside an EUI-64 IPv6 address" enforce the first two; "no fixture contains the capturing site's ISP infrastructure" (which keeps the list of literals scrubbed in 0.1.1) and "no fixture host name ends in a residential ISP's domain" enforce the fourth.

## Data, and promote or leave

`src/Graph.Emitter.Network/data/` is production. Kinds: CloudReservations and IpSources (written by hand from the pages their sources cite), SpecialUse, CloudRanges (gzip), Oui, Ports (harvested by `Update-NetworkGraphData`). Each file: `formatVersion`, `kind`, `maxAgeDays`, `pulled` (UTC date), `sources`, then the data.

Harvests write the user cache (`$env:LOCALAPPDATA\NetworkGraph\data`, `$script:NetworkGraphDataUserRoot`), which wins over the bundled copy. Nothing moves into `src/` except through `Invoke-Build UpdateData` (harvest, then copy). When `Invoke-Build CheckData` fails, an agent reports the stale rows and the command, and runs UpdateData only if its task is about that data; otherwise it leaves it. Tests repoint the user root to TestDrive (tests/TestSetup.ps1) and never touch the real cache.

A hand-written data file changes only after re-reading its source pages; update each source's `pulled` date when you do.

## Graph contract

docs/graph-shape.md is the contract; `$script:NetworkGraphNodeContract` in the psm1 holds the same per-kind property lists and `Add-NetworkGraphNode` refuses anything else. Pester parses the doc's tables and compares them with real nodes. Changing a node property means changing the doc, the psm1 table and the tests together. Property names match TerraformGraph's `ConvertTo-TerraformResourceGraph` (Id, Kind first; edges From, To, Kind; graph Root, Nodes, Edges, NodeCount, EdgeCount). Every edge has Source (after Kind): the Source of the row that asserted it, never empty. Interface and Route Ids are built on InterfaceKey (Windows interface GUID, Linux ifindex), never on the renameable alias.

## Argument completion

Every parameter with a fixed vocabulary has a ValidateSet (or an ArgumentCompleter that never touches the network). Module.Tests.ps1 asserts completion through TabExpansion2, including `-Cloud` and `-Tool`, and the `.build.ps1` task completers (registered the same way as TerraformGraph's: the first `Invoke-Build` in a session registers them).

## Manual check list

`manual-check-list.md`: section 0 is setup (0.1 fresh import: version and exported commands; update its Expect whenever the version or exports change). Then one section per area, items numbered `N.M`, append-only: never renumber, mark a removed item "(removed in x.y.z)". Sections 2 to 24 are one exported function each, in FunctionsToExport order; a new function joins or starts a section from 25 on (skill manual-check-list). Each item: one-line purpose, a self-contained code block, run in the shell it is pasted into, whose first line is `Set-Location 'C:\__Code\Graph.Emitter.Network'`, then `Remove-Module Graph.Emitter.Network` and the import from `src` with `-Force`, an Expect line you have seen yourself (or "not run: needs network" when you could not run it), and a `Pester:` line naming the covering test by its It description (or `Pester: none`). Update "Module version" and "Last updated" at the top. Jerry runs it on Windows. No block uses `pwsh -Command { ... }` (it prints nothing pasted into a console); the fresh process per item came from TerraformGraph, where P/Invoke pins a Go DLL in the process, and this module has no DLL, so `Import-Module -Force` is enough (skill `manual-check-list`).

## Do not

- Commit, push, tag, branch or release.
- Bundle or download a binary; add Add-Type or compiled code.
- Write harvested data into `src/` by hand, or edit a fixture to make a test pass.
- Call the network or a real tool from a test that is not tagged Live.
