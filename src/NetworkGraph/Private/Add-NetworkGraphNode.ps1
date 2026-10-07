function Add-NetworkGraphNode {
    # Not exported. Adds a node to -State (ConvertTo-NetworkGraph's working set) or merges into the
    # node with the same Id: a property the node has as $null takes the new value, OpenPorts is a
    # union, others keep their first value. Properties are exactly Id, Kind, Name, the kind's list
    # in $script:NetworkGraphNodeContract, then Source; an unknown property name is an error, so
    # the node shape cannot drift from docs/graph-shape.md. Returns the node.
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        [string]
        $Kind,

        [Parameter(Mandatory)]
        [string]
        $Id,

        [string]
        $Name,

        [string]
        $Source,

        [System.Collections.IDictionary]
        $Property = @{}
    )

    $allowed = $script:NetworkGraphNodeContract[$Kind]
    if ($null -eq $allowed) { throw [System.ArgumentException]::new("Unknown node kind '$Kind'.") }
    foreach ($key in $Property.Keys) {
        if ($key -notin $allowed) { throw [System.ArgumentException]::new("Node kind $Kind has no property '$key' in the graph contract.") }
    }

    $existing = $null
    if ($State.ById.TryGetValue($Id, [ref]$existing)) {
        if (-not $existing.Name -and $Name) { $existing.Name = $Name }
        if (-not $existing.Source -and $Source) { $existing.Source = $Source }
        foreach ($key in $Property.Keys) {
            $value = $Property[$key]
            if ($key -eq 'OpenPorts') {
                $existing.OpenPorts = @(@($existing.OpenPorts) + @($value) | Where-Object { $null -ne $_ } | Sort-Object -Unique)
            }
            elseif ($null -eq $existing.$key -and $null -ne $value) {
                $existing.$key = $value
            }
        }
        return $existing
    }

    $shape = [ordered]@{ PSTypeName = 'NetworkGraph.Node'; Id = $Id; Kind = $Kind; Name = ($Name ? $Name : $Id) }
    foreach ($key in $allowed) { $shape[$key] = $Property[$key] }
    $shape['Source'] = $Source ? $Source : $null
    $node = [pscustomobject]$shape
    $State.ById[$Id] = $node
    $State.Nodes.Add($node)
    $node
}
