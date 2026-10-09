- **Cytoscape.js** — the strongest fit. Built for graphs, has good layouts (cose, dagre, cola), handles incremental add of nodes and edges without redrawing everything, MIT licensed, and it's one minified file around 350 KB you ship under `assets/`. This is what I'd pick.
- **vis-network** — easiest to get something on screen, physics layout looks nice when nodes arrive live, but gets slow past a few thousand nodes and the project is less active.
- **D3 force layout** — most control, most code. Worth it only if you want a custom look; for a module renderer it's overkill.

#--------------------------------


There isn't one standard; there are about four families, and they differ mainly on where the edge lives and how typed things are.

**Property graph** — the Neo4j / Cypher model, and what you already have. A node is an id, one or more labels (your `Kind`), and a bag of key-value properties. An edge is an id, a type, a from, a to, and its own property bag. Edges are first-class objects, not nested inside nodes. This is the one your three repos already converged on without naming it, so you're on solid ground.

**JSON Graph Format (JGF)** — the closest thing to a plain-JSON property-graph standard. Top level has `graph` with `directed`, `type`, `label`, `metadata`, then `nodes` as a map keyed by id (each with `label` and `metadata`) and `edges` as a list of `source`, `target`, `relation`, `metadata`. Cytoscape's own input format is nearly the same idea: `elements.nodes[].data` and `elements.edges[].data` with `id`, `source`, `target`. If you want something to say "we emit X," JGF is the honest answer, and your current shape maps onto it with a rename or two.

**GraphML / GEXF** — the XML ones. GraphML is what Gephi, yEd and NetworkX exchange; typed attributes declared up front with `<key>` elements, then `<node>` and `<edge>`. Worth an exporter, not worth being your native shape.

**RDF / triples** — subject, predicate, object. Everything is an edge, nodes are just URIs, schema lives in a separate ontology (RDFS/OWL). Powerful and verbose; it's where the word "ontology" you've been using actually comes from, but it's a poor fit for a PowerShell object pipeline.

So the schema for a node in your world should be: `Id` (stable, opaque, derived from a real identifier, never a display name), `Kind` (one label; a `Labels` array if you ever need more), `Name` (display), domain properties, then `Source` (provenance), and that's what all three modules now do except TerraformGraph. Edge: `Id`, `Kind` (the relation), `From`, `To`, properties, `Source`. Graph envelope: `Root`, `Nodes`, `Edges`, `Findings`, counts, plus a `Schema` or `FormatVersion` field so a renderer can refuse a shape it doesn't understand.

The one thing worth borrowing from the formal world that you don't have yet: a **declared vocabulary** of allowed `Kind` values per module, with a Pester test that every node and edge uses one. That's what your ONTOLOGY.md is already becoming; make it machine-readable (a small JSON next to it) and the renderer can drive colour and shape from it rather than hard-coding.




















