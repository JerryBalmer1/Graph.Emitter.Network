function Add-NetworkGraphEdge {
    # Not exported. Adds one edge { From, To, Kind, Source } to -State unless the same From, To and
    # Kind are there (the first row to assert an edge keeps its Source); Kind must be one of
    # $script:NetworkGraphEdgeKinds, case included (PascalCase, as TerraformGraph). Source is the
    # Source of the row that asserted the relation (docs/graph-shape.md) and may not be empty.
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        [string]
        $From,

        [Parameter(Mandatory)]
        [string]
        $To,

        [Parameter(Mandatory)]
        [string]
        $Kind,

        [Parameter(Mandatory)]
        [string]
        $Source
    )

    if ($Kind -cnotin $script:NetworkGraphEdgeKinds) { throw [System.ArgumentException]::new("Unknown edge kind '$Kind'.") }
    if (-not $State.EdgeKeys.Add("$From|$To|$Kind")) { return }
    $State.Edges.Add([pscustomobject]@{
            PSTypeName = 'NetworkGraph.Edge'
            From       = $From
            To         = $To
            Kind       = $Kind
            Source     = $Source
        })
}
