function Get-SubnetParent {
    <#
    .SYNOPSIS
        Finds the most specific prefix in a list that contains each given prefix.

    .DESCRIPTION
        For every -Cidr, Parent is the longest prefix in -In that strictly contains it, or $null.
        Without -In, the -Cidr list is its own candidate list, which turns a flat list of prefixes
        into a tree (each row's Parent is the next prefix up).

    .PARAMETER Cidr
        Prefixes (or bare addresses) to place. Accepts the pipeline and objects with a Cidr
        property.

    .PARAMETER In
        Candidate parents. Default: the -Cidr list itself.

    .EXAMPLE
        Get-SubnetParent 10.0.1.0/24, 10.0.0.0/16, 10.0.1.128/25

        10.0.1.0/24 under 10.0.0.0/16, 10.0.0.0/16 under nothing, 10.0.1.128/25 under 10.0.1.0/24.

    .EXAMPLE
        Get-SubnetParent 10.0.1.7 -In 10.0.0.0/16, 10.0.1.0/24

        10.0.1.7/32 under 10.0.1.0/24.

    .OUTPUTS
        NetworkGraph.SubnetLink: Cidr, Parent.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.SubnetLink')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]
        $Cidr,

        [string[]]
        $In
    )

    begin { $items = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($item in $Cidr) { $items.Add((Resolve-NetworkGraphPrefix -Cidr $item)) } }
    end {
        $candidates = if ($PSBoundParameters.ContainsKey('In')) { @($In | ForEach-Object { Resolve-NetworkGraphPrefix -Cidr $_ }) } else { $items.ToArray() }
        foreach ($item in $items) {
            $best = $null
            foreach ($candidate in $candidates) {
                if ((Get-NetworkGraphPrefixRelation -Left $candidate -Right $item) -ne 'Contains') { continue }
                if ($null -eq $best -or $candidate.PrefixLength -gt $best.PrefixLength) { $best = $candidate }
            }
            [pscustomobject]@{
                PSTypeName = 'NetworkGraph.SubnetLink'
                Cidr       = $item.Cidr
                Parent     = $best ? $best.Cidr : $null
            }
        }
    }
}
