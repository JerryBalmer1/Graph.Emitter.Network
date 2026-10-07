function Add-NetworkGraphEdge {
    # Not exported. Adds one edge { From, To, Kind } to -State unless the same triple is there;
    # Kind must be one of $script:NetworkGraphEdgeKinds.
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
        $Kind
    )

    if ($Kind -notin $script:NetworkGraphEdgeKinds) { throw [System.ArgumentException]::new("Unknown edge kind '$Kind'.") }
    if (-not $State.EdgeKeys.Add("$From|$To|$Kind")) { return }
    $State.Edges.Add([pscustomobject]@{
            PSTypeName = 'NetworkGraph.Edge'
            From       = $From
            To         = $To
            Kind       = $Kind
        })
}
