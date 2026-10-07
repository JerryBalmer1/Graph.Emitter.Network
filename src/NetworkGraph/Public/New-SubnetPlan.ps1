function New-SubnetPlan {
    <#
    .SYNOPSIS
        Splits a prefix into subnets: equal parts, or variable-length (VLSM) by host count.

    .DESCRIPTION
        -PrefixLength cuts the parent into every subnet of that length. -Hosts and -Requirement
        size each subnet for its host count plus the addresses -Cloud reserves (Azure and AWS 5,
        GCP 4, None 2 for IPv4), round up to a power of two and never below the cloud minimum
        subnet, then place them largest first, each aligned on its own size. Largest-first
        placement of power-of-two blocks never fragments, so a plan fits exactly when the sizes add
        up to no more than the parent. When they do not, the terminating error (PlanDoesNotFit)
        names the shortfall in addresses.

        Offline and deterministic: the same input gives the same plan.

    .PARAMETER Cidr
        The parent prefix.

    .PARAMETER PrefixLength
        Equal split: every subnet of this length (at most 65536 of them).

    .PARAMETER Hosts
        VLSM: host counts, one per subnet. Subnets are named subnet-1, subnet-2, ... in the order
        given.

    .PARAMETER Requirement
        VLSM with names: a hashtable of name = host count.

    .PARAMETER Cloud
        None (default), Azure, AWS or GCP: whose reservations and minimum size apply.

    .EXAMPLE
        New-SubnetPlan 10.0.0.0/22 -Hosts 250, 120, 60, 25

        Four subnets (/24, /25, /26, /27) and the rest of the /22 in Remaining.

    .EXAMPLE
        New-SubnetPlan 10.0.0.0/23 -Hosts 250, 120, 60, 25 -Cloud Azure

        PlanDoesNotFit: 544 addresses needed, 512 available, short by 32.

    .EXAMPLE
        New-SubnetPlan 10.1.0.0/16 -Requirement @{ web = 200; app = 400; data = 50 } -Cloud AWS

    .OUTPUTS
        NetworkGraph.SubnetPlan: Parent, Cloud, Subnets (NetworkGraph.PlannedSubnet: every
        NetworkGraph.Subnet property plus Name, Parent, RequestedHosts), Remaining (free prefixes
        after the last subnet, largest aligned blocks).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Returns a plan object; changes no state.')]
    [CmdletBinding(DefaultParameterSetName = 'Hosts')]
    [OutputType('NetworkGraph.SubnetPlan')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [string]
        $Cidr,

        [Parameter(Mandatory, ParameterSetName = 'Equal')]
        [ValidateRange(0, 128)]
        [int]
        $PrefixLength,

        [Parameter(Mandatory, ParameterSetName = 'Hosts')]
        [ValidateRange(1, [long]::MaxValue)]
        [long[]]
        $Hosts,

        [Parameter(Mandatory, ParameterSetName = 'Requirement')]
        [System.Collections.IDictionary]
        $Requirement,

        [ValidateSet('None', 'Azure', 'AWS', 'GCP')]
        [string]
        $Cloud = 'None'
    )

    process {
        $parent = Resolve-NetworkGraphPrefix -Cidr $Cidr
        $toIp = { param($value) ConvertFrom-NetworkGraphIpValue -Value $value -Version $parent.Version }

        # Requests: Name, RequestedHosts, PrefixLength.
        $requests = [System.Collections.Generic.List[object]]::new()
        if ($PSCmdlet.ParameterSetName -eq 'Equal') {
            if ($PrefixLength -lt $parent.PrefixLength -or $PrefixLength -gt $parent.Bits) {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.ArgumentException]::new("Cannot split $($parent.Cidr) into /$PrefixLength subnets: the length must be between $($parent.PrefixLength) and $($parent.Bits)."),
                        'PrefixLengthOutOfRange', [System.Management.Automation.ErrorCategory]::InvalidArgument, $PrefixLength))
            }
            $parts = [System.Numerics.BigInteger]::Pow(2, $PrefixLength - $parent.PrefixLength)
            if ($parts -gt 65536) {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.ArgumentException]::new("$($parent.Cidr) into /$PrefixLength is $parts subnets; New-SubnetPlan stops at 65536. Split an intermediate prefix first."),
                        'TooManySubnets', [System.Management.Automation.ErrorCategory]::LimitsExceeded, $PrefixLength))
            }
            for ($i = 1; $i -le [int]$parts; $i++) {
                $requests.Add([pscustomobject]@{ Name = "subnet-$i"; RequestedHosts = $null; PrefixLength = $PrefixLength })
            }
        }
        else {
            $wanted = if ($PSCmdlet.ParameterSetName -eq 'Hosts') {
                $i = 0
                foreach ($count in $Hosts) { $i++; [pscustomobject]@{ Name = "subnet-$i"; RequestedHosts = $count } }
            }
            else {
                foreach ($key in $Requirement.Keys) { [pscustomobject]@{ Name = [string]$key; RequestedHosts = [long]$Requirement[$key] } }
            }
            # Usable addresses per prefix length under this cloud, measured on a real block.
            $usableAt = @{}
            $rule = (Get-NetworkGraphDataDocument -Kind CloudReservations)['clouds'][$Cloud]
            $longest = $parent.Bits
            if ($parent.Version -eq 4 -and $null -ne $rule['maxPrefixLength']) { $longest = [int]$rule['maxPrefixLength'] }
            foreach ($item in @($wanted)) {
                $length = $null
                for ($candidate = $longest; $candidate -ge $parent.PrefixLength; $candidate--) {
                    if (-not $usableAt.ContainsKey($candidate)) {
                        $probe = Resolve-NetworkGraphPrefix -Ip (& $toIp $parent.Network) -PrefixLength $candidate
                        $usableAt[$candidate] = (New-NetworkGraphSubnet -Prefix $probe -Cloud $Cloud 3>$null).Usable
                    }
                    if ($usableAt[$candidate] -ge $item.RequestedHosts) { $length = $candidate; break }
                }
                if ($null -eq $length) {
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                            [System.InvalidOperationException]::new("$($item.Name) needs $($item.RequestedHosts) hosts, more than all of $($parent.Cidr) gives under $Cloud. Use a larger parent prefix."),
                            'PlanDoesNotFit', [System.Management.Automation.ErrorCategory]::LimitsExceeded, $item.Name))
                }
                $requests.Add([pscustomobject]@{ Name = $item.Name; RequestedHosts = $item.RequestedHosts; PrefixLength = $length })
            }
        }

        # Largest first (shortest prefix); ties keep the order given.
        $ordered = @($requests | Sort-Object -Stable -Property PrefixLength)
        $needed = [System.Numerics.BigInteger]::Zero
        foreach ($request in $ordered) { $needed = $needed + [System.Numerics.BigInteger]::Pow(2, $parent.Bits - $request.PrefixLength) }
        if ($needed -gt $parent.Size) {
            $sizes = ($ordered | ForEach-Object { "$($_.Name) /$($_.PrefixLength)" }) -join ', '
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new("Plan does not fit: $needed addresses needed ($sizes), $($parent.Cidr) has $($parent.Size) under $Cloud; short by $($needed - $parent.Size) addresses. Use a larger parent prefix or fewer hosts."),
                    'PlanDoesNotFit', [System.Management.Automation.ErrorCategory]::LimitsExceeded, $parent.Cidr))
        }

        $next = $parent.Network
        $subnets = foreach ($request in $ordered) {
            $prefix = Resolve-NetworkGraphPrefix -Ip (& $toIp $next) -PrefixLength $request.PrefixLength
            $next = $prefix.Last + 1
            $subnet = New-NetworkGraphSubnet -Prefix $prefix -Cloud $Cloud
            $subnet.PSObject.TypeNames.Insert(0, 'NetworkGraph.PlannedSubnet')
            $subnet | Add-Member -NotePropertyMembers ([ordered]@{ Name = $request.Name; Parent = $parent.Cidr; RequestedHosts = $request.RequestedHosts }) -PassThru
        }

        # What is left, as the largest aligned blocks.
        $remaining = [System.Collections.Generic.List[string]]::new()
        while ($next -le $parent.Last) {
            $hostBits = 0
            while ($hostBits -lt $parent.Bits) {
                $size = [System.Numerics.BigInteger]::Pow(2, $hostBits + 1)
                if (-not [System.Numerics.BigInteger]::Remainder($next, $size).IsZero -or $next + $size - 1 -gt $parent.Last) { break }
                $hostBits++
            }
            $remaining.Add(('{0}/{1}' -f (& $toIp $next), ($parent.Bits - $hostBits)))
            $next = $next + [System.Numerics.BigInteger]::Pow(2, $hostBits)
        }

        [pscustomobject]@{
            PSTypeName = 'NetworkGraph.SubnetPlan'
            Parent     = $parent.Cidr
            Cloud      = $Cloud
            Subnets    = @($subnets)
            Remaining  = $remaining.ToArray()
        }
    }
}
