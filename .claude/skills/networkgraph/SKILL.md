---
name: networkgraph
description: Repo-only skill for working on the Graph.Emitter.Network module in this repository (adding or changing a function, parser, fixture, data file or graph property). Not shipped; the module's user skill is src/Graph.Emitter.Network/skills/networkgraph/SKILL.md.
---

# Working on Graph.Emitter.Network

Read CLAUDE.md first; it holds the rules. This skill is the procedure.

## Before you finish any change

1. Fresh-process Pester: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -CI"`. All green, and say the counts.
2. `Invoke-Build Analyze`: no errors.
3. `manual-check-list.md`: update or append items for any changed exported surface; bump item 0.1 when the version or exports change; run each block you touched and write only the Expect you saw. `ONTOLOGY.md` and `README.md` in the same task: follow the `manual-check-list`, `ontology-doc` and `readme` skills.
4. Stage with `git add`. Never commit, push, tag, branch or release.

## Adding an exported function

- `src/Graph.Emitter.Network/Public/<Verb-Noun>.ps1`, one function, comment-based help with an example.
- Add it to `FunctionsToExport` in the psd1, inside its group (Calculate, Observe, Graph and data).
- Fixed-vocabulary parameters get a ValidateSet; add a TabExpansion2 assertion in tests/Module.Tests.ps1.
- `tests/<Verb-Noun>.Tests.ps1`, dot-sourcing tests/TestSetup.ps1 in BeforeAll.
- Update the export count in Module.Tests.ps1 and in checklist item 0.1.

## Adding or changing a native tool parser

1. Capture real output into `tests/fixtures/<tool>.<os>.txt` (`.json`/`.xml` when the tool emits that). On Windows run the tool; on Linux use a container (`docker run mcr.microsoft.com/powershell`, `apt-get install` the tool). Scrub personal data without changing the format.
2. Prefer the tool's structured output. Regex only when there is none; name the fixture in the parser's comment.
3. Parser in `Private/ConvertFrom-NetworkGraph<Tool>Output.ps1`, returning the shared row shape (`New-NetworkGraph*Row`).
4. Call the tool only through `Invoke-NetworkGraphNative`; put the command line in Source.
5. Tests: the parser on the fixture, and the public function through `Set-NativeFixture` plus `Mock Resolve-NetworkGraphTool -ModuleName Graph.Emitter.Network`. Anything touching the real network or a real tool is `-Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE)`.

## Changing data

- Harvested kinds (SpecialUse, CloudRanges, Oui, Ports): change the harvester in `Private/Get-NetworkGraph*Harvest.ps1`, then `Invoke-Build UpdateData -Kind <kind>` (network) and stage `src/Graph.Emitter.Network/data`. Never edit those files by hand.
- Hand-written kinds (CloudReservations, IpSources): re-read the source pages, edit, update each source's `pulled`.
- `Invoke-Build CheckData` must pass.

## Changing the graph

Change docs/graph-shape.md, `$script:NetworkGraphNodeContract` in the psm1 and the tests together. No node property named Address, Count, Length or any System.Array member.

Every edge has a Source: `Add-NetworkGraphEdge -Source` is mandatory, and the Source is that of the row that asserted the relation (the table in docs/graph-shape.md "Edge properties"). Interface and Route Ids are built on `InterfaceKey`, never on the alias: a parser that names an interface by index or name takes `-KeyMap` (`Get-NetworkGraphInterfaceKeyMap`) and passes `-InterfaceKey` to its row builder.
