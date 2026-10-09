function Test-SubnetOverlap {
    <#
    .SYNOPSIS
        Compares every pair of prefixes: Overlaps, Contains, ContainedBy or Disjoint.

    .DESCRIPTION
        One row per pair, in input order (first with second, first with third, ...). Relation reads
        Left to Right. Two CIDR blocks either nest or do not touch, so Overlaps means the two are
        the same block; Contains and ContainedBy are the nesting cases, which also share addresses.
        IPv4 and IPv6 prefixes are always Disjoint. Use -OverlapOnly to drop the Disjoint rows.

    .PARAMETER Cidr
        Two or more prefixes. Accepts the pipeline, and objects with a Cidr property (Get-Subnet,
        New-SubnetPlan subnets).

    .PARAMETER OverlapOnly
        Return only pairs that share addresses.

    .EXAMPLE
        Test-SubnetOverlap 10.0.0.0/16, 10.0.1.0/24, 10.1.0.0/16

        10.0.0.0/16 Contains 10.0.1.0/24; the other two pairs are Disjoint.

    .OUTPUTS
        NetworkGraph.SubnetOverlap: Left, Right, Relation.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.SubnetOverlap')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]
        $Cidr,

        [switch]
        $OverlapOnly
    )

    begin { $all = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($item in $Cidr) { $all.Add((Resolve-NetworkGraphPrefix -Cidr $item)) } }
    end {
        for ($i = 0; $i -lt $all.Count; $i++) {
            for ($j = $i + 1; $j -lt $all.Count; $j++) {
                $relation = Get-NetworkGraphPrefixRelation -Left $all[$i] -Right $all[$j]
                if ($OverlapOnly -and $relation -eq 'Disjoint') { continue }
                [pscustomobject]@{
                    PSTypeName = 'NetworkGraph.SubnetOverlap'
                    Left       = $all[$i].Cidr
                    Right      = $all[$j].Cidr
                    Relation   = $relation
                }
            }
        }
    }
}
