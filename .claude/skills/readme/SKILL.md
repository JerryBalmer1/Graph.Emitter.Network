---
name: readme
description: Keep README.md, the sysadmin door to NetworkGraph, in step with the code. Use whenever a public function, parameter, parameter set, wrapped tool, bundled data file, or Invoke-Build task is added, changed, or removed, and before reporting any task that touched one.
---

# README

`README.md` is the door for people who run networks: sysadmins, network and platform engineers, CI authors. It says what each command does, which tool it wraps on Windows and Linux, shows a pasteable example, and states numbers that were measured. The agent and ontology story lives in `ONTOLOGY.md` (kept by the `ontology-doc` skill), not here.

## When to update it

In the same task as any change to:
- an exported function (add, rename, remove) or its parameters, parameter sets, defaults or output type
- a wrapped tool or a .NET floor: which native tool a command runs on Windows or Linux, which path `-Tool Auto` takes, or a command line that appears in `Source`
- bundled data (`data/cloud-reservations.json`, `data/special-use.json`, `data/cloud-ranges.json.gz`, `data/oui.json`, `data/ports.json`, `data/ip-sources.json`) or a new data kind
- an Invoke-Build task (`Test`, `Analyze`, `Assemble`, `UpdateData`, `CheckData`, ...)
- a number the README quotes (node counts, usable addresses, finding counts)
- a Planned item being built (drop "(Planned)" and show the command)

If the task touches none of these, leave the file alone.

## Rules

- Line 1 is the ontology callout and nothing else: one `>` line that says the module was built as an ontology layer for AI agents and links `ONTOLOGY.md`. Keep it to one line. Never move it below the banner.
- Each door opens with a banner pointing at the other: README line 1 is the `>` callout linking `ONTOLOGY.md`, and `ONTOLOGY.md` opens with its own banner and a link back here. That is all Pester ("keeps the two doors") checks. Further mentions of ontology or links to `ONTOLOGY.md` later in the README are allowed where they help a reader; the explanation itself (the agent story, terminology, facts and opinions) still belongs in `ONTOLOGY.md`.
- The CI example stays on the first screen: one line that exits non-zero when any two subnets in `subnets.txt` overlap, with the exit codes stated. If `Test-SubnetOverlap` or its `-OverlapOnly` output changes, fix and rerun it (with a clean file, an overlapping file, an invalid line and a missing file).
- Each public function is shown in the section for its area (Calculate, Observe, Graph, Data, Agent skills) with at least one example you have run. Use exact command and parameter names; never paraphrase a parameter. The Observe tool table names the native tool on Windows and on Linux and the .NET floor for every observe command.
- A section for something not built yet is a `###` heading in its area ending "(Planned)", one or two sentences, no example and no invented command name.
- Observe examples use addresses anyone can run against (1.1.1.1, 127.0.0.1, example.com) and never scan a network the reader may not own. Output pasted from your machine follows the fixture scrub rule in CLAUDE.md: no host name, public address or device MAC of yours.
- Numbers are measured, dated and attributed to the run that produced them (for example "on this machine on 2026-10-07"). Never round a count you can state exactly.
- "Source version" matches `ModuleVersion` in the psd1.
- The Invoke-Build task list matches `.build.ps1`; README names the tasks, `.build.ps1` and CLAUDE.md are the source of truth for what they do. Releases are Jerry's; README states no release steps.

## Procedure

1. Read the psd1 `FunctionsToExport` and the parameter blocks of whatever changed. Function code is one function per file, named for the function: `src/NetworkGraph/Public/<Verb-Noun>.ps1` for an exported command, `src/NetworkGraph/Private/<Verb-Noun>.ps1` for a helper. Edit the file named for the function, never `NetworkGraph.psm1`: it is state and wiring only, and `Invoke-Build Assemble` builds the single psm1 that ships.
2. Edit the matching README section. Run every example you add or change in a fresh `pwsh -NoProfile` process and paste only output you saw.
3. Check that line 1 is still the `>` callout linking `ONTOLOGY.md`: `Get-Content README.md -TotalCount 1`.
4. Run `Invoke-Build CheckData` and read the rows that are not Fresh. If the README quotes bundled data that is stale, say so in your report instead of quoting it as current. Follow "Promote or leave" below for each such row.
5. Stage README.md. Do not commit.
6. In your report, list the README sections you changed, one line each, and the CheckData counts (Fresh, Stale, Unsourced).

## Promote or leave

Harvests write to the user cache under `$env:LOCALAPPDATA\NetworkGraph\data` (development); `src/` is production. For every Stale or Unsourced row from `Invoke-Build CheckData`:
- Put the row (File, Kind, Pulled, AgeDays, MaxAgeDays) and the fix line CheckData printed in your report.
- Run the fix (`Invoke-Build UpdateData -Kind <kind>`, or re-reading a hand-written file's sources) only if your task is about that data. Otherwise report the row and leave it; a README edit is not a reason to refresh data.
- Nothing moves into `src/` except through `Invoke-Build UpdateData`, and you commit nothing.
- Give the human both commands in the report, pasteable: `Invoke-Build CheckData` and the fix.

## Do not

- Do not add ontology prose, terminology tables, or the facts/opinions discussion here.
- Do not put manual checklist items here; link to `manual-check-list.md` by item number if needed.
- Do not edit the shipped skill (`src/NetworkGraph/skills/networkgraph/SKILL.md`) to mirror README wording; it has its own audience, and changes to it follow the code, not the README.
