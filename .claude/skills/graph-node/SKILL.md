---
name: graph-node
description: How to produce, declare, validate and read graph/1 envelopes with GraphNode, the base graph shape shared by every graph module (emitters such as TerraformGraph, NetworkGraph, AzureDevOpsGraph; consumers such as GraphRenderer). Use any time this repo writes or reads a graph.json envelope or an ontology.yaml, builds nodes or edges, or reports GraphNode problem codes.
version: 0.1.0
---

# GraphNode for emitters and consumers

GraphNode owns the shape: one Node, one Edge, one Envelope (`schema: graph/1`), the schema your `ontology.yaml` must satisfy, and a validator in PowerShell and Go. Your repo produces or reads that shape; it never redefines it. If the shape does not fit what you need, propose a change to GraphNode; do not work around it locally.

`reference/` beside this file holds a complete example to open: `envelope.example.json` (a valid envelope) and `ontology.example.yaml` (the ontology it names; in your repo the file is `ontology.yaml`, which is the name the example envelope uses).

## When to use

Any time a repo produces or reads graph/1 envelopes: building nodes and edges from a source, writing a layer, writing or changing `ontology.yaml`, validating output in tests or CI, or loading layers to draw, diff or merge them.

## Depend on GraphNode

PowerShell (7.4+). Until GraphNode is on a feed, import it from a sibling checkout:

```powershell
Import-Module C:\__Code\GraphNode\src\GraphNode\GraphNode.psd1
```

Once it is on a feed, declare it in your psd1 instead: `RequiredModules = @(@{ ModuleName = 'GraphNode'; ModuleVersion = '0.1.0' })`. Do not copy GraphNode's files into your module.

Go (1.24+). Import the package and pin it to a tag in `go.mod`, never `latest` or a branch:

```
go get github.com/JerryBalmer1/GraphNode/graph@v0.1.0
```

The package embeds the schemas, so `graph.Validate` needs no files on disk.

## Produce an envelope

PowerShell:

```powershell
Import-Module C:\__Code\GraphNode\src\GraphNode\GraphNode.psd1
$layer = Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ'
$vnet  = New-GraphNode -Id 'vnet:a' -Kind VNet -Name vnet-a -Properties @{ cidr = '10.0.0.0/16' } -Source @{ tool = 'az'; command = 'az network vnet show -n vnet-a' }
$snet  = New-GraphNode -Id 'snet:a' -Kind Subnet -Name snet-a -Properties @{ cidr = '10.0.1.0/24' }
$edge  = New-GraphEdge -From $vnet -To $snet -Kind contains
$env   = New-GraphEnvelope -Module Example -Version 0.1.0 -Layer $layer -Ontology 'ontology.yaml' -Nodes $vnet, $snet -Edges $edge
Export-Graph $env -Path ".\layers\$($layer -replace ':', '-')\graph.json"
```

- `New-GraphNode -Id -Kind` are required; `-Name`, `-Properties`, `-Source`, `-Findings`, `-Layer` (sets `stamp.layer`) are optional and omitted from the JSON when not given. `New-GraphNode`, `New-GraphEdge` and `New-GraphEnvelope` write any `[datetime]` or `[DateTimeOffset]` given as `-Layer` or as a top-level `-Properties` value as a UTC stamp `yyyy-MM-ddTHH:mm:ssZ` (whole seconds), so `-Layer (Get-Date)` is safe. Strings are written as given.
- `New-GraphEdge -From -To -Kind` takes node objects or id strings and sets the edge id for you.
- `New-GraphEnvelope -Module -Layer` are required; it sets `schema: graph/1` and fills `counts` (`nodes`, `edges`, `byKind`). `-Version`, `-Root`, `-Ontology`, `-Findings` (envelope-level findings) are optional.
- `Export-Graph` runs `Test-Graph` first and throws on any problem unless `-Force`; it writes UTF-8 without BOM, LF line endings, and creates the directory.

Go: `env := graph.NewEnvelope(module, version, layer)`, append `graph.Node{ID: ..., Kind: ...}` and `graph.NewEdge(from, to, kind)`, then `env.Recount()` and `graph.Save(path, env)`. `NewEnvelope` keeps the lists non-nil so they serialise as `[]`.

Rules:
- Edge id is `from|to|kind`, exactly: `vnet:a|snet:a|contains`. Both validators reject anything else (`edge-id`). Build it with `New-GraphEdge` or `graph.NewEdge` / `graph.EdgeID`, never by hand. Do not put `|` in a node id; the schema does not forbid it yet, but it makes the edge id ambiguous.
- Node id stability across layers is your job. The same real thing must get the same id in every layer, or a diff sees a delete and an add. Write the rule for each Kind as `idRule` in your `ontology.yaml` (`"vnet:<name>"`) and follow it.
- Kind names match `^[A-Za-z][A-Za-z0-9_.-]*$`. `New-GraphNode` and `New-GraphEdge` reject anything else.
- One envelope per layer: each run of your emitter writes one complete envelope of what it saw, never a patch. `layer` is required and must sort in time order as a string. Stamps are UTC ending `Z`: `layer`, `stamp.layer`, `stamp.firstSeen`, `stamp.lastSeen` and ActionRun `startedAt` and `finishedAt` must match `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?Z$` (`2026-10-08T00:00:00Z`); a `+hh:mm` offset or no zone is a `stamp` problem. Keep one width across layers (whole seconds, as the builders write) so string order is time order. Put the same value in `stamp.layer` (`-Layer`) if you stamp nodes.
- Required: Node `id`, `kind`; Edge `id`, `kind`, `from`, `to`; Envelope `schema`, `module`, `layer`, `nodes`, `edges`. Everything else is optional and tolerated when absent, so leave out what you do not know rather than writing empty values.
- `source` is a list of `{tool, command, path, file, line}`, all optional. `findings` is a list of `{kind, severity, message, target}`; `kind` and `message` are required by the Go types.

## Declare an ontology

Your repo ships one `ontology.yaml` that declares every Kind, edge Kind and finding Kind you emit. It is validated against GraphNode's `ontology.schema.json`; unknown keys fail.

```yaml
module: Example
version: 0.1.0
kinds:
  VNet:
    description: A virtual network.
    idRule: "vnet:<name>"
    properties: [cidr]
    display: { color: "#4a90e2", shape: round-rectangle }
  Subnet:
    idRule: "snet:<name>"
    properties:
      - { name: cidr, type: string, required: true }
    display: { color: "#2ec4b6", shape: hexagon }
    actions:
      - name: attach
        description: Attach a VM to this subnet.
        inputs: { vm: VM }
        trigger: manual
        permissions: [network.write]
edgeKinds:
  contains: { from: [VNet], to: [Subnet] }
findingKinds:
  unused-subnet: { severity: info }
```

- `kinds` is required. Each Kind may have `description`, `idRule`, `properties` (names, or `{name, type, required, description}` with `type` one of string, integer, number, boolean, object, array), `display` and `actions`.
- `display` is `{color, shape, icon, label, collapsed}`; `label` is a template where `{name}` and `{properties.x}` substitute. Display lives here, per Kind (and per edge Kind), and never on a node or edge: the node and edge schemas reject a `display` key (`schema`). A consumer resolves it from the ontology, so changing a colour is an ontology change, not a re-emit.
- `actions` are `{name, description, inputs, trigger, permissions}`; `trigger` is `manual`, `on-change`, `schedule:<cron>` or `event:<name>`. Actions are declared only; running one is the ledger's job and produces an ActionRun node.
- `edgeKinds` give `from` and `to` as lists of Kind names, plus optional `description` and `display`.
- `findingKinds` give an optional `description` and `severity` (`info`, `warning`, `error`).
- If you emit a base Kind (ActionRun), declare it under `kinds` too so it has a display.
- `envelope.ontology` names the file (`"ontology": "ontology.yaml"`), as a path or URL. A relative path is relative to the directory of the envelope file, so `ontology.yaml` means the file beside `graph.json`, and `../ontology.yaml` one level up. Set it with `New-GraphEnvelope -Ontology`. `schema` stays `graph/1` regardless of your ontology's version.

## Validate

PowerShell:
- `Test-Graph $env` or `Test-Graph -Path .\graph.json` runs the pure-PowerShell checks and returns `Valid`, `Problems` (each `Code`, `Path`, `Message`) and `Strict`. No binary needed.
- `Test-Graph ... -Strict` also runs the `graphnode` binary for full JSON Schema validation, including the base Kind schemas. It needs the binary built in the GraphNode checkout (`src\GraphNode\bin\win-x64\graphnode.exe` or `bin/linux-x64/graphnode`); if it is not built, `-Strict` throws `Test-Graph -Strict needs the graphnode binary: build the graphnode binary; see README` (GraphNode's README); on a platform with no binary (macOS today) it throws `no graphnode binary for this platform (win-x64, linux-x64)`. CI should run `-Strict` (or `graphnode validate`).

Go and CI:
- `graph.Validate(env)` or `graph.ValidateBytes(data)` returns `[]graph.Problem` (`Code`, `Path`, `Message`), nil when conformant. `graph.ValidateOntology(doc)` checks a decoded ontology.
- `graphnode validate <graph.json>` and `graphnode validate-ontology <ontology.yaml>` print a JSON array of `{code, path, message}` (`[]` when clean) and exit 0 when clean, 1 on any problem, 2 on a usage or read error. `graphnode schema` lists the schema names; `graphnode schema <name>` prints one; `graphnode version` prints the version.

Problem codes (the same in both validators; a code one reports and the other does not is a GraphNode bug, report it):

| Code | Means |
|---|---|
| `schema` | A required field is missing or wrong (`schema` not `graph/1`, no `module`, `layer`, `nodes` or `edges`, a node or edge without its required fields, a node or edge Kind name that does not match the pattern, a `display` key on a node or edge), or, with `-Strict` / Go, any other JSON Schema violation; Go checks the full base Kind schemas, so it can find more `schema` problems than pure `Test-Graph`. Also the code for a file that is not JSON. |
| `duplicate-node` | Two nodes in the envelope have the same `id`. |
| `duplicate-edge` | Two edges in the envelope have the same `id`. |
| `dangling-edge` | An edge's `from` or `to` is not the id of a node in the same envelope. |
| `edge-id` | An edge's `id` is not `from|to|kind`. |
| `counts` | `counts.nodes` or `counts.edges` disagrees with the lists. |
| `kind` | A base Kind node is missing what its schema requires (ActionRun `action`, `startedAt`; Category `label`). |
| `stamp` | `layer`, `stamp.layer`, `stamp.firstSeen`, `stamp.lastSeen`, or ActionRun `startedAt` or `finishedAt` is not a UTC ISO-8601 stamp ending `Z`. |

What the validators do not check yet: that a node's or edge's Kind is declared in your `ontology.yaml`, and that an edge's endpoints match its edge Kind's `from` / `to`. Those rules below are yours to keep.

## Read an envelope

- `Import-Graph .\graph.json` returns the envelope with `nodes`, `edges` and `findings` always present (empty arrays when missing). Validate it with `Test-Graph` before trusting it.
- `Import-Graph` (PowerShell's JSON reader) turns ISO-8601 strings such as `layer`, `startedAt` and `finishedAt` into `[datetime]`. A valid `Z` stamp exports back unchanged and `Test-Graph` accepts it; an offset stamp (invalid anyway) would come back rewritten in the local time zone. Compare layers as the strings in the file.
- `Get-GraphSchema envelope` (or `node`, `edge`, `ontology`, `action-run`, `category`) returns a schema as a hashtable; `-Raw` returns the JSON text; `-List` lists all six.
- Go: `graph.Load(path)` or `graph.Decode(r)` returns `*graph.Envelope`, filling empty lists; `env.NodeIndex()` maps id to index. `graph.SchemaNames()` and `graph.SchemaBytes(name)` expose the embedded schemas.
- Tolerate every optional field being absent. Resolve display, edge rules and actions from the ontology the envelope names, not from the nodes.

## Base Kinds you may emit

| Kind | When | Properties | Edges |
|---|---|---|---|
| `ActionRun` | One execution of an action declared in an ontology, recorded by whatever ran it. Emit it only when your repo actually runs actions. | Required `action` (`<Kind>.<action name>`, e.g. `Subnet.attach`), `startedAt`; optional `finishedAt`, `status` (`running`, `succeeded`, `failed`, `cancelled`), `actor`, `inputs`. `startedAt` and `finishedAt` are UTC stamps ending `Z`. | `performed-on` to each target node; `produced` to each node it created or changed. |
| `Category` | Never from an emitter. Only the taxonomy module writes it. | Required `label`; optional `description`. | Kinds join it by `is-a` edges. |

Any other Kind is yours and is declared in your `ontology.yaml`. Never add your own Kinds to GraphNode.

## What not to do

- No per-emitter node types. One Node shape with a `kind` string; what a Kind carries goes in `properties` and is declared in `ontology.yaml`.
- No display on nodes or edges (`color`, `shape`, `icon`, ...): the schema rejects it. Display lives in `ontology.yaml`.
- No edge without both endpoints in the same envelope. If the other end belongs to another module, emit a node for it or leave the edge out; `dangling-edge` is not a warning.
- No hand-built edge ids. Use `New-GraphEdge`, `graph.NewEdge` or `graph.EdgeID`.
- No Kind, edge Kind or finding Kind that is not declared in your `ontology.yaml`.
- No `Category` nodes from an emitter, and no edits to another module's layers.

## Changes

- 0.1.0: initial; stamps (`layer`, `stamp.*`, ActionRun `startedAt`, `finishedAt`) must be UTC ending `Z`, builders convert `[datetime]`, new code `stamp`; `display` on a node or edge is rejected (`schema`); pure `Test-Graph` checks the edge Kind pattern; a relative `envelope.ontology` path is relative to the envelope file's directory; `-Strict` errors for an unbuilt binary or an unsupported platform.
