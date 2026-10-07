function Get-SubnetChildren {
    <#
    .SYNOPSIS
        Lists the prefixes in a list that sit inside each given prefix.

    .DESCRIPTION
        For every -Cidr, the prefixes in -In it strictly contains. By default only direct children:
        a prefix with another candidate between it and -Cidr is left out. -Recurse returns every
        descendant, each with its own direct Parent, so the rows form a tree under -Cidr.

    .PARAMETER Cidr
        Parent prefixes. Accepts the pipeline and objects with a Cidr property.

    .PARAMETER In
        Candidate children.

    .PARAMETER Recurse
        Every descendant, not only direct children.

    .EXAMPLE
        Get-SubnetChildren 10.0.0.0/16 -In 10.0.1.0/24, 10.0.1.128/25, 10.1.0.0/24

        10.0.1.0/24 only; with -Recurse also 10.0.1.128/25 under 10.0.1.0/24.

    .OUTPUTS
        NetworkGraph.SubnetLink: Cidr (the child), Parent.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Name fixed by the module spec; Get-SubnetParent returns one parent, this returns the set.')]
    [CmdletBinding()]
    [OutputType('NetworkGraph.SubnetLink')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]
        $Cidr,

        [Parameter(Mandatory)]
        [string[]]
        $In,

        [switch]
        $Recurse
    )

    begin { $candidates = @($In | ForEach-Object { Resolve-NetworkGraphPrefix -Cidr $_ }) }
    process {
        foreach ($text in $Cidr) {
            $root = Resolve-NetworkGraphPrefix -Cidr $text
            $inside = @($candidates | Where-Object { (Get-NetworkGraphPrefixRelation -Left $root -Right $_) -eq 'Contains' } | Sort-Object PrefixLength, Network)
            foreach ($child in $inside) {
                # Direct parent: the longest prefix among root and the other descendants holding it.
                $parent = $root
                foreach ($other in $inside) {
                    if ((Get-NetworkGraphPrefixRelation -Left $other -Right $child) -eq 'Contains' -and $other.PrefixLength -gt $parent.PrefixLength) { $parent = $other }
                }
                if (-not $Recurse -and $parent -ne $root) { continue }
                [pscustomobject]@{
                    PSTypeName = 'NetworkGraph.SubnetLink'
                    Cidr       = $child.Cidr
                    Parent     = $parent.Cidr
                }
            }
        }
    }
}
