---
name: manual-check-list
description: Maintain manual-check-list.md at the repo root, the paste-and-verify checklist for every exported function and parameter set. Use whenever an exported function, parameter, parameter set, default display, or documented example is added, changed, or removed.
---

# Manual check list

`manual-check-list.md` at the repo root is the human-run companion to Pester. Pester proves the code works; the checklist proves the documented way of using the module works when a person pastes it into a terminal. Every item is something Jerry copies, runs, and eyeballs against an Expect line.

## When to update it

In the same task as any change to:
- an exported function (add, rename, remove)
- a parameter, parameter set, alias, default value, or ValidateSet (including `-Tool Auto|Native|DotNet` and which path Auto takes on a platform)
- default display properties (Update-TypeData in `NetworkGraph.psm1`)
- an example in comment-based help or README

If the task touches none of these, leave the file alone. Never update it in a separate task; the checklist and the code land together.

## File layout

```
# NetworkGraph manual check list

Module version: <ModuleVersion from psd1>
Last updated: <YYYY-MM-DD>

## 0 Setup
### 0.1 Fresh import: version and exports
...

## 1 First checks
### 1.1 Get-Subnet: Azure /24
...

## 2 ConvertFrom-SubnetMask
### 2.1 ConvertFrom-SubnetMask: -Mask
### 2.2 ConvertFrom-SubnetMask: a non-contiguous mask
...

## 5 Get-Subnet
### 5.1 Get-Subnet: -Cidr (default set, no cloud)
### 5.2 Get-Subnet: -Address -Mask
...
```

Section 0 is always Setup; item 0.1's Expect lists the version and every exported command, so it changes whenever either does. Section 1 is the first checks: the README's examples and cross-cutting behaviour (0.1.0 and 0.1.1 contracts). Sections 2 to 24 are one exported function each, in FunctionsToExport order (Calculate, then Observe, then Graph and data). From section 25 on, a section covers a family of functions that work together or one release's cross-cutting contracts. A new function joins its family's section; a new family or release theme gets the next number. Within a section, one `###` item per parameter set or distinct behaviour worth seeing, numbered `N.M`. Never renumber existing items; append new ones and leave removed items' numbers unused with a one-line note "(removed in 0.x.0)" so references stay stable.

## Item format

Every item has exactly these parts, in this order:

```
### 5.2 Get-Subnet: -Address -Mask

The Mask parameter set: an address and a dotted mask.

```powershell
pwsh -NoProfile -Command {
    Set-Location 'C:\__Code\NetworkGraph'
    Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
    Import-Module .\src\NetworkGraph\NetworkGraph.psd1 -Force
    Get-Subnet -Address 192.168.1.77 -Mask 255.255.255.192 | Format-List Cidr, FirstUsable, LastUsable, Usable
}
```

Expect: Cidr `192.168.1.64/26`, FirstUsable `192.168.1.65`, LastUsable `192.168.1.126`, Usable `62`.

Pester: "takes -Address with -PrefixLength or -Mask"
```

Rules:
- The code block is self-contained. It starts a fresh process (`pwsh -NoProfile -Command { ... }`, CLAUDE.md) and its first three lines are the setup lines above, so it works from any shell and can never resolve to an installed NetworkGraph module. No item depends on a previous item having run. Items 1.1 to 1.14 predate the `Remove-Module` line; leave them as they are.
- Objects cross the process boundary deserialized. Format inside the block (`Format-Table`, `Format-List`, or a `'{0} {1}' -f` line) so the screen shows what the Expect describes.
- Expect is one or two sentences describing what appears on screen: counts, property names, a specific value, or the exact error text. Not "it works". Observe output depends on the machine: give the shape and an example ("a line like `Rows 66, ...`"), never a host name, a public address or a MAC from your machine (the fixture scrub rule in CLAUDE.md applies to Expect lines too).
- Say which tool produced an observe item's output (the `Source` line), and when an item needs network access say so in its purpose line. Say what the item shows when a tool is missing (no nmap, no dig) if that changes the output.
- Pester names the test(s) under tests/ that cover the same behaviour, by their It description in quotes, copied exactly (templated names such as "converts <Mask> to /<Length>" included); mark Live tests "(Live)". If none exists, write `Pester: none` so the gap is visible. Do not write a test just to fill this line; report the gap instead.
- Error cases are items too (non-contiguous mask, no .NET floor on this platform, too many addresses to expand). Expect states the error text.
- Use documentation and loopback addresses (192.0.2.0/24, 127.0.0.1, 10.0.0.0/8) for everything that can use them. Never scan or trace a network you do not own; a listener the item needs is a `TcpListener` on loopback, started and stopped inside the block. If an item needs a throwaway directory, create it under $env:TEMP inside the block and remove it at the end of the same block.

## Procedure

1. Read manual-check-list.md and the current psd1 FunctionsToExport.
2. For each function you added or changed, read its parameter block and help examples from the file named for it. Function code is one function per file, named for the function: `src/NetworkGraph/Public/<Verb-Noun>.ps1` for an exported command, `src/NetworkGraph/Private/<Verb-Noun>.ps1` for a helper. Edit the file named for the function, never `NetworkGraph.psm1`: it is state and wiring only, and `Invoke-Build Assemble` builds the single psm1 that ships.
3. Add or edit items. Run every block you add or edit exactly as written (save it to a temp `.ps1` and run `pwsh -NoProfile -File` on it) and confirm the output matches Expect before writing it down. Fix the Expect line, not the output.
4. Update Module version and Last updated at the top, and the "Verified for" line with what you ran and on which OS.
5. Stage the file. Do not commit.
6. In your task report, list the item numbers added, changed, or marked removed, one line each.

## Do not

- Do not put checklist items anywhere else (README, ONTOLOGY.md, CLAUDE.md, help). Link to them by number if needed.
- Do not paraphrase Pester test names; copy them.
- Do not write an Expect you have not seen.
