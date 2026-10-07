function Get-NetworkGraphPrefixRelation {
    # Not exported. How prefix Left relates to prefix Right (Resolve-NetworkGraphPrefix results):
    # Overlaps (the same block), Contains, ContainedBy or Disjoint. Two CIDR blocks either nest or
    # do not touch, so Overlaps only ever means identical. Different IP versions are Disjoint.
    param(
        [Parameter(Mandatory)]
        $Left,

        [Parameter(Mandatory)]
        $Right
    )

    if ($Left.Version -ne $Right.Version) { return 'Disjoint' }
    if ($Left.Network -eq $Right.Network -and $Left.PrefixLength -eq $Right.PrefixLength) { return 'Overlaps' }
    if ($Left.PrefixLength -lt $Right.PrefixLength -and $Right.Network -ge $Left.Network -and $Right.Last -le $Left.Last) { return 'Contains' }
    if ($Right.PrefixLength -lt $Left.PrefixLength -and $Left.Network -ge $Right.Network -and $Left.Last -le $Right.Last) { return 'ContainedBy' }
    'Disjoint'
}
