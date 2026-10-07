# NetworkGraph

PowerShell 7.4+ module: subnet math with cloud reservations, auditable wrappers over the network tools already installed, and a graph of what a host can see. Pure PowerShell: no Go, no C#, no DLL, no bundled binaries of any kind.

Requires PowerShell 7.4+, Pester 6.1.0+, InvokeBuild. PSScriptAnalyzer for `Invoke-Build Analyze`.

## Working rules

- Agents edit and stage only. No commit, push, branch, tag or release; Jerry does those.
- Keep changes scoped. No drive-by refactors.
- Run Pester in a fresh process, never in the shell that imported the module: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -CI"` (or `Invoke-Build`, which does the same).
- Every change to an exported function, parameter, parameter set, default, ValidateSet, default view or documented example updates `manual-check-list.md` in the same task (see "Manual check list").
- Every data file carries a top-level `sources` array of `{ url, title, pulled }`; no data without a source URL.

## Naming

Node types never have a property named `Address`, `Count`, `Length`, or any other member of `System.Array` (member access on an array of nodes would hit the array's own member); use a qualified name (`Ip`, `InterfaceName`, `OpenPorts`). Pester "has no node property named Address, Count, Length or another System.Array member" enforces it against docs/graph-shape.md. Row objects from observe commands follow the same rule.

## Layout

```
.build.ps1                       Invoke-Build: Test (default), Analyze, Assemble, UpdateData, CheckData
.claude/skills/networkgraph/     repo-only agent skill (working in this repo; not shipped)
docs/graph-shape.md              node and edge contract, and where it came from (TerraformGraph)
docs/design.md                   design notes and judgement calls
src/NetworkGraph/
  NetworkGraph.psd1              FunctionsToExport is the export list, grouped by the three groups
  NetworkGraph.psm1              module-scope state, type data and wiring only; dot-sources Private/ then Public/
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
- Parse structured output where the tool offers it (`ip -j`, `mtr --json`, `nmap -oX`, cmdlet objects). Regex only as the last resort, and every regex parser is pinned by a fixture test per platform. Fixtures are real output captured from the tool (`tests/fixtures/<tool>.<os>.txt`), never invented; scrub personal data (MAC device bytes, public addresses) without changing the format, and say so. CI never calls a tool: tests that touch the real network or tools are tagged `Live` and skip unless `NETWORKGRAPH_LIVE` is set (`$env:NETWORKGRAPH_LIVE = 1; Invoke-Pester -Path .\tests -TagFilter Live`).
- Windows and Linux are supported; macOS is untested and docs say so.

## Data, and promote or leave

`src/NetworkGraph/data/` is production. Kinds: CloudReservations and IpSources (written by hand from the pages their sources cite), SpecialUse, CloudRanges (gzip), Oui, Ports (harvested by `Update-NetworkGraphData`). Each file: `formatVersion`, `kind`, `maxAgeDays`, `pulled` (UTC date), `sources`, then the data.

Harvests write the user cache (`$env:LOCALAPPDATA\NetworkGraph\data`, `$script:NetworkGraphDataUserRoot`), which wins over the bundled copy. Nothing moves into `src/` except through `Invoke-Build UpdateData` (harvest, then copy). When `Invoke-Build CheckData` fails, an agent reports the stale rows and the command, and runs UpdateData only if its task is about that data; otherwise it leaves it. Tests repoint the user root to TestDrive (tests/TestSetup.ps1) and never touch the real cache.

A hand-written data file changes only after re-reading its source pages; update each source's `pulled` date when you do.

## Graph contract

docs/graph-shape.md is the contract; `$script:NetworkGraphNodeContract` in the psm1 holds the same per-kind property lists and `Add-NetworkGraphNode` refuses anything else. Pester parses the doc's tables and compares them with real nodes. Changing a node property means changing the doc, the psm1 table and the tests together. Property names match TerraformGraph's `ConvertTo-TerraformResourceGraph` (Id, Kind first; edges From, To, Kind; graph Root, Nodes, Edges, NodeCount, EdgeCount).

## Argument completion

Every parameter with a fixed vocabulary has a ValidateSet (or an ArgumentCompleter that never touches the network). Module.Tests.ps1 asserts completion through TabExpansion2, including `-Cloud` and `-Tool`, and the `.build.ps1` task completers (registered the same way as TerraformGraph's: the first `Invoke-Build` in a session registers them).

## Manual check list

`manual-check-list.md`: section 0 is setup (0.1 fresh import: version and exported commands; update its Expect whenever the version or exports change). Then one section per area, items numbered `N.M`, append-only: never renumber, mark a removed item "(removed in x.y.z)". Each item: one-line purpose, a self-contained code block that starts a fresh process (`pwsh -NoProfile -Command { ... }`) and imports from `src`, an Expect line you have seen yourself, and a `Pester:` line naming the covering test by its It description (or `Pester: none`). Update "Module version" and "Last updated" at the top. Jerry runs it on Windows.

## Do not

- Commit, push, tag, branch or release.
- Bundle or download a binary; add Add-Type or compiled code.
- Write harvested data into `src/` by hand, or edit a fixture to make a test pass.
- Call the network or a real tool from a test that is not tagged Live.
