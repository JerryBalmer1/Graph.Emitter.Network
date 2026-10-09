---
name: ontology-doc
description: Keep ONTOLOGY.md, the agent and ontology door to Graph.Emitter.Network, in step with the code. Use whenever the Id scheme, a node or edge kind, a finding kind, a terminating error id, a typed row or its Source, a bundled data shape (the data/ files and their sources), or a planned ontology feature changes.
---

# ONTOLOGY.md

`ONTOLOGY.md` at the repo root is the door for readers who came for the agent story: one Id for an address across sockets, trace hops, registries and cloud ranges, with a Source on every row. It is dense and must explain in one screen what the module is. `README.md` (kept by the `readme` skill) is the sysadmin door and never repeats this material.

## When to update it

In the same task as any change to:
- the canonical Id scheme (any node Id format in docs/graph-shape.md "Node properties")
- a node kind, an edge kind or a node property (`$script:NetworkGraphNodeContract`, `$script:NetworkGraphEdgeKinds` in the psm1) or a property the terminology table names
- a finding kind (`$script:NetworkGraphFindingKinds`: `SubnetOverlap`, `BelowCloudMinimum`, `NonCloudPublicConnection`, `WildcardListener`, `RouteWithoutInterface`)
- a terminating error id (`FullyQualifiedErrorId`) the "What agents get" section lists, or a new one an agent would branch on
- what an observe command puts in `Source`, or which tool `-Tool Auto` picks on a platform
- the shape or provenance fields of bundled data: any file in `src/Graph.Emitter.Network/data/` (`formatVersion`, `kind`, `maxAgeDays`, `pulled`, `sources`), or a new data kind
- a shape difference from TerraformGraph closing or opening (docs/graph-shape.md "Where it came from")
- a "Not here yet" item shipping, slipping or changing target version

## Rules

- Each door opens with a banner pointing at the other. First non-blank line: the banner, one `>` line in the same style as README's line 1. Second non-blank line: the link back to `README.md`. Keep both first; Pester ("keeps the two doors") checks them and nothing else, so further links to README.md, and README mentioning ontology after its line 1, are allowed.
- Sections stay in this order: The ontology was already there; What this is; Why a host's network is an unusually good ontology source; What agents get; Terminology; Facts and opinions; Not here yet. The first one is written for someone who works on ontologies or agent systems and has never thought of a host's network tables and the address registries as a source: the realisation, not a definition.
- Terminology names match exported names exactly. The "In the module" column holds only backticked names of three kinds: an exported command (`Get-NetworkGraphData`), a typed object or one of its properties (`NetworkGraph.IPAddressInfo.CloudPrefix`; `NetworkGraph.Node.<property>` resolves against the graph contract), or a data file path relative to the module or repo root (`data/cloud-ranges.json.gz`). Pester ("resolves every term in ONTOLOGY.md's terminology table") resolves every one and fails on anything else, so rename the table in the same task as the code. No `|` inside a cell, even in backticks: it splits the row.
- The term list is Id, node, edge, finding, graph, row, Source, tool, data file, sources, reservation, cloud range, in that order. Adding a term means updating the Pester expectation in the same task.
- Facts versus opinions: tool output, the IANA and IEEE registries, the clouds' published ranges and reservation rules, and RDAP answers are facts; `data/ip-sources.json`, the finding rules and the `-Tool Auto` choices (docs/design.md) are opinions held as data or code with reasons. A new data file goes in one list or the other, never both.
- Every claim about errors, network access or provenance must be true of the current code. Check the error id with `Select-String -Path .\src\Graph.Emitter.Network\Private\*.ps1, .\src\Graph.Emitter.Network\Public\*.ps1` and run the command to see its `FullyQualifiedErrorId` before naming it; say plainly which errors have no id yet.
- The graph shape stays compatible with TerraformGraph's so one renderer draws both. If a change would open a new difference, record it in docs/graph-shape.md and in "What agents get" and report it; never change either module's shape silently to make them agree.
- Dense, plain sentences. No marketing words. A table beats a paragraph.

## Procedure

1. Read the change (the files named for the functions that changed, docs/graph-shape.md, the psm1 contract tables, the data file) and the current ONTOLOGY.md. Function code is one function per file, named for the function: `src/Graph.Emitter.Network/Public/<Verb-Noun>.ps1` for an exported command, `src/Graph.Emitter.Network/Private/<Verb-Noun>.ps1` for a helper. Edit the file named for the function, never `Graph.Emitter.Network.psm1`: it is state and wiring only, and `Invoke-Build Assemble` builds the single psm1 that ships.
2. Edit the affected sections. Keep the banner and backlink first.
3. Run the two Ontology tests in a fresh process: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Module.Tests.ps1 -FullNameFilter 'Ontology*' -CI"`.
4. Stage ONTOLOGY.md. Do not commit.
5. In your report, list the sections and terminology rows you changed.

## Promote or leave

Harvests write to the user cache under `$env:LOCALAPPDATA\NetworkGraph\data` (development); `src/` is production. When a provenance claim depends on bundled data, run `Invoke-Build CheckData`, and for every file it reports Stale or Unsourced:
- Put its row (File, Kind, Pulled, AgeDays, MaxAgeDays) and the fix line CheckData printed in your report.
- Run the fix (`Invoke-Build UpdateData -Kind <kind>`, or re-reading a hand-written file's sources) only if your task is about that data. Otherwise report the row and leave it; an ONTOLOGY.md edit is not a reason to refresh data.
- Nothing moves into `src/` except through `Invoke-Build UpdateData`, and you commit nothing.
- Give the human both commands in the report, pasteable: `Invoke-Build CheckData` and the fix.

## Do not

- Do not copy README material (install, examples, tool tables) into ONTOLOGY.md; link README instead.
- Do not list a term the module has no name for; if a concept is planned, put it under "Not here yet" with a target version and point the term at the closest existing name. Target is "not scheduled" until Jerry names a version; never invent one.
