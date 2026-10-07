function ConvertTo-NetworkGraph {
    <#
    .SYNOPSIS
        Turns calculate and observe output into one graph of nodes, edges and findings.

    .DESCRIPTION
        Takes any mix of Get-NetworkHost, Get-NetworkInterface, Get-NetworkRoute,
        Get-NetworkConnection, Get-NetworkNeighbor, Trace-NetworkPath, Test-NetworkPort,
        Invoke-NetworkScan, Test-NetworkPath, Resolve-NetworkName, Get-ExternalIpAddress,
        Test-IPAddress, Get-Subnet and New-SubnetPlan output, and returns one NetworkGraph.Graph.
        The node and edge property names are the ones ConvertTo-TerraformResourceGraph in
        TerraformGraph uses (Id, Kind first; edges From, To, Kind); docs/graph-shape.md is the
        contract. Offline: remote addresses are classified with the bundled data (Test-IPAddress),
        nothing is looked up on the network.

        Node kinds and Ids: Host <hostname>; Interface <host>/if/<name>; Subnet <cidr>@<cloud>;
        Route <host>/route/<cidr>/<next hop or on-link>/<interface>; Hop hop/<target>/<n>;
        Connection <host>/conn/<protocol>/<local ip>:<port>/<remote ip>:<port> (IPv6 in [brackets],
        remote * for a listener); Process
        <host>:<pid>; RemoteHost <ip>, or dns:<name> for a DNS name; Cloud cloud/<cloud>;
        Asn AS<number>. Observed rows belong to -HostName (default this computer) unless a
        Get-NetworkHost object names the host.

        Edge kinds: contains (host to interface, process, connection and route; interface to
        route; subnet to interface and to planned subnet), routes-to (route to next hop; host to
        its external address), hops-to (host to first hop, hop to hop), connects-to (connection to
        remote host; interface to neighbour), owned-by (connection to process), resolves-to (DNS
        name to address or name), belongs-to (remote host to cloud and to ASN).

        Findings: SubnetOverlap (two subnets share addresses and neither is the other's planned
        parent), BelowCloudMinimum, NonCloudPublicConnection (a connection to a public address in
        no harvested cloud range), WildcardListener (TCP listening on 0.0.0.0 or ::),
        RouteWithoutInterface.

    .PARAMETER InputObject
        Objects from the commands above. Anything else is skipped with one warning per type.

    .PARAMETER HostName
        The host observed rows belong to. Default: this computer's name.

    .EXAMPLE
        Get-NetworkConnection -Resolve | ConvertTo-NetworkGraph

    .EXAMPLE
        $graph = @(Get-NetworkHost; Get-NetworkConnection; Trace-NetworkPath 1.1.1.1) | ConvertTo-NetworkGraph
        $graph.Findings | Format-Table Finding, NodeId, Detail

    .OUTPUTS
        NetworkGraph.Graph: Root, Nodes (NetworkGraph.Node), Edges (NetworkGraph.Edge: From, To,
        Kind), Findings (NetworkGraph.Finding: Finding, NodeId, RelatedId, Detail), and the script
        properties NodeCount, EdgeCount, FindingCount.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.Graph')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]
        $InputObject,

        [string]
        $HostName = [System.Net.Dns]::GetHostName()
    )

    begin { $items = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($item in $InputObject) { if ($null -ne $item) { $items.Add($item) } } }
    end {
        $state = [pscustomobject]@{
            ById     = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Nodes    = [System.Collections.Generic.List[object]]::new()
            Edges    = [System.Collections.Generic.List[object]]::new()
            EdgeKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        $findings = [System.Collections.Generic.List[object]]::new()
        $addFinding = {
            param($Finding, $NodeId, $RelatedId, $Detail)
            $findings.Add([pscustomobject]@{ PSTypeName = 'NetworkGraph.Finding'; Finding = $Finding; NodeId = $NodeId; RelatedId = $RelatedId; Detail = $Detail })
        }
        $is = { param($Item, $Type) $Item.PSObject.TypeNames -contains $Type }

        $hostItem = $items | Where-Object { & $is $_ 'NetworkGraph.Host' } | Select-Object -First 1
        if ($hostItem) { $HostName = $hostItem.HostName }
        $hostId = $HostName.ToLowerInvariant()
        $ensureHost = {
            Add-NetworkGraphNode -State $state -Kind Host -Id $hostId -Name $HostName -Property @{ HostName = $HostName } | Out-Null
            $hostId
        }
        $ensureInterface = {
            param($Name, $Source)
            $id = "$(& $ensureHost)/if/$Name"
            $null = Add-NetworkGraphNode -State $state -Kind Interface -Id $id -Name $Name -Source $Source -Property @{ InterfaceName = $Name }
            Add-NetworkGraphEdge -State $state -From $hostId -To $id -Kind contains
            $id
        }
        $ensureRemote = {
            param($Ip, $Property, $Source)
            $address = (ConvertTo-NetworkGraphIpValue -Ip $Ip -Unmap).Ip
            $properties = @{ Ip = $address }
            if ($Property) { foreach ($key in $Property.Keys) { if ($null -ne $Property[$key]) { $properties[$key] = $Property[$key] } } }
            $name = $properties['RemoteHost'] ? $properties['RemoteHost'] : $address
            $null = Add-NetworkGraphNode -State $state -Kind RemoteHost -Id $address -Name $name -Source $Source -Property $properties
            $address
        }
        $ensureDnsName = {
            param($Name, $Source)
            $id = "dns:$($Name.TrimEnd('.').ToLowerInvariant())"
            $null = Add-NetworkGraphNode -State $state -Kind RemoteHost -Id $id -Name $Name -Source $Source -Property @{ RemoteHost = $Name }
            $id
        }
        $ensureSubnet = {
            param($Cidr, $Cloud, $Source)
            $prefix = Resolve-NetworkGraphPrefix -Cidr $Cidr
            $subnet = New-NetworkGraphSubnet -Prefix $prefix -Cloud $Cloud 3>$null
            $id = "$($prefix.Cidr)@$Cloud"
            $null = Add-NetworkGraphNode -State $state -Kind Subnet -Id $id -Name $prefix.Cidr -Source $Source -Property @{
                Cidr = $prefix.Cidr; Cloud = $Cloud; PrefixLength = $prefix.PrefixLength; Usable = $subnet.Usable; BelowCloudMinimum = $subnet.BelowCloudMinimum
            }
            $id
        }

        # Expand containers into their rows, host first.
        $queue = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $items) {
            if (& $is $item 'NetworkGraph.Host') {
                $null = Add-NetworkGraphNode -State $state -Kind Host -Id $hostId -Name $item.HostName -Source $item.Source -Property @{ HostName = $item.HostName; Os = $item.Os }
                foreach ($child in @($item.Interfaces) + @($item.Routes)) { if ($child) { $queue.Add($child) } }
            }
            elseif (& $is $item 'NetworkGraph.SubnetPlan') { foreach ($child in @($item.Subnets)) { $queue.Add($child) } }
            else { $queue.Add($item) }
        }

        $hops = [System.Collections.Generic.List[object]]::new()
        $skipped = @{}
        foreach ($item in $queue) {
            if (& $is $item 'NetworkGraph.Subnet') {
                $id = & $ensureSubnet $item.Cidr $item.Cloud 'Get-Subnet'
                if (& $is $item 'NetworkGraph.PlannedSubnet') {
                    $node = $state.ById[$id]
                    $node.Name = "$($item.Name) $($item.Cidr)"
                    $node.Source = 'New-SubnetPlan'
                    $parentId = & $ensureSubnet $item.Parent $item.Cloud 'New-SubnetPlan'
                    Add-NetworkGraphEdge -State $state -From $parentId -To $id -Kind contains
                }
            }
            elseif (& $is $item 'NetworkGraph.Interface') {
                $id = & $ensureInterface $item.Name $item.Source
                $null = Add-NetworkGraphNode -State $state -Kind Interface -Id $id -Property @{
                    Ip = @($item.Ip); PrefixLength = @($item.PrefixLength); MacAddress = $item.MacAddress; Vendor = $item.Vendor; Status = $item.Status
                }
                for ($i = 0; $i -lt @($item.Ip).Count; $i++) {
                    $ip = @($item.Ip)[$i]
                    $length = @($item.PrefixLength)[$i]
                    $scope = @(Find-NetworkGraphSpecialUse -Address (ConvertTo-NetworkGraphIpValue -Ip $ip)) | Select-Object -First 1
                    if ($scope -and $scope['scope'] -in 'Loopback', 'LinkLocal') { continue }
                    if ($length -ge ($ip.Contains(':') ? 128 : 32)) { continue }
                    $subnetId = & $ensureSubnet "$ip/$length" 'None' $item.Source
                    Add-NetworkGraphEdge -State $state -From $subnetId -To $id -Kind contains
                }
            }
            elseif (& $is $item 'NetworkGraph.Route') {
                $owner = & $ensureHost
                $id = "$owner/route/$($item.Cidr)/$($item.NextHop ? $item.NextHop : 'on-link')/$($item.Interface ? $item.Interface : '-')"
                $null = Add-NetworkGraphNode -State $state -Kind Route -Id $id -Name $item.Cidr -Source $item.Source -Property @{
                    Destination = $item.Destination; PrefixLength = $item.PrefixLength; NextHop = $item.NextHop; InterfaceName = $item.Interface; Metric = $item.Metric
                }
                if ($item.Interface) {
                    $interfaceId = & $ensureInterface $item.Interface $item.Source
                    Add-NetworkGraphEdge -State $state -From $interfaceId -To $id -Kind contains
                }
                else {
                    Add-NetworkGraphEdge -State $state -From $owner -To $id -Kind contains
                    & $addFinding 'RouteWithoutInterface' $id $null "Route to $($item.Cidr) names no interface."
                }
                if ($item.NextHop) {
                    $remoteId = & $ensureRemote $item.NextHop $null $item.Source
                    Add-NetworkGraphEdge -State $state -From $id -To $remoteId -Kind routes-to
                }
            }
            elseif (& $is $item 'NetworkGraph.Connection') {
                $owner = & $ensureHost
                $endpoint = { param($Ip, $Port) ($Ip.Contains(':') ? "[$Ip]" : $Ip) + ":$Port" }
                $local = & $endpoint $item.LocalIp $item.LocalPort
                $remote = $item.RemoteIp ? (& $endpoint $item.RemoteIp $item.RemotePort) : '*'
                $id = "$owner/conn/$($item.Protocol.ToLowerInvariant())/$local/$remote"
                $null = Add-NetworkGraphNode -State $state -Kind Connection -Id $id -Name "$($item.Protocol) $local -> $remote" -Source $item.Source -Property @{
                    Protocol = $item.Protocol; LocalIp = $item.LocalIp; LocalPort = $item.LocalPort; RemoteIp = $item.RemoteIp; RemotePort = $item.RemotePort; State = $item.State; ProcessId = $item.ProcessId
                }
                Add-NetworkGraphEdge -State $state -From $owner -To $id -Kind contains
                if ($null -ne $item.ProcessId) {
                    $processId = "${owner}:$($item.ProcessId)"
                    $null = Add-NetworkGraphNode -State $state -Kind Process -Id $processId -Name ($item.ProcessName ? $item.ProcessName : "$($item.ProcessId)") -Source $item.Source -Property @{
                        ProcessId = $item.ProcessId; ProcessName = $item.ProcessName
                    }
                    Add-NetworkGraphEdge -State $state -From $owner -To $processId -Kind contains
                    Add-NetworkGraphEdge -State $state -From $id -To $processId -Kind owned-by
                }
                if ($item.RemoteIp) {
                    $extra = @{}
                    foreach ($key in 'RemoteHost', 'Cloud', 'Service', 'Asn', 'Owner') { if ($item.PSObject.Properties[$key]) { $extra[$key] = $item.$key } }
                    $remoteId = & $ensureRemote $item.RemoteIp $extra $item.Source
                    Add-NetworkGraphEdge -State $state -From $id -To $remoteId -Kind connects-to
                }
                if ($item.Protocol -eq 'Tcp' -and $item.State -eq 'Listen' -and $item.LocalIp -in '0.0.0.0', '::') {
                    $who = $item.ProcessName ? " ($($item.ProcessName))" : ''
                    & $addFinding 'WildcardListener' $id $null "TCP port $($item.LocalPort) listens on every address ($($item.LocalIp))$who."
                }
            }
            elseif (& $is $item 'NetworkGraph.Neighbor') {
                $remoteId = & $ensureRemote $item.Ip @{ MacAddress = $item.MacAddress; Vendor = $item.Vendor } $item.Source
                if ($item.Interface) {
                    $interfaceId = & $ensureInterface $item.Interface $item.Source
                    Add-NetworkGraphEdge -State $state -From $interfaceId -To $remoteId -Kind connects-to
                }
            }
            elseif (& $is $item 'NetworkGraph.Hop') { $hops.Add($item) }
            elseif (& $is $item 'NetworkGraph.Port') {
                $extra = @{}
                if ($item.Target -and $item.Target -ne $item.Ip) { $extra.RemoteHost = $item.Target }
                if ($item.Open) { $extra.OpenPorts = @([int]$item.Port) }
                $null = & $ensureRemote $item.Ip $extra $item.Source
            }
            elseif (& $is $item 'NetworkGraph.PathTest') {
                if ($item.Ip) { $null = & $ensureRemote $item.Ip (($item.Target -ne $item.Ip) ? @{ RemoteHost = $item.Target } : $null) $item.Source }
            }
            elseif (& $is $item 'NetworkGraph.IPAddressInfo') {
                $null = & $ensureRemote $item.Ip @{ Cloud = $item.Cloud; Service = $item.Service; Asn = $item.Asn; Owner = $item.Owner } 'Test-IPAddress'
            }
            elseif (& $is $item 'NetworkGraph.ExternalIp') {
                $remoteId = & $ensureRemote $item.Ip @{ Asn = $item.Asn; Owner = $item.Owner } $item.Source
                Add-NetworkGraphEdge -State $state -From (& $ensureHost) -To $remoteId -Kind routes-to
            }
            elseif (& $is $item 'NetworkGraph.DnsRecord') {
                switch ($item.Type) {
                    { $_ -in 'A', 'AAAA' } {
                        $nameId = & $ensureDnsName $item.Name $item.Source
                        $remoteId = & $ensureRemote $item.Data @{ RemoteHost = $item.Name } $item.Source
                        Add-NetworkGraphEdge -State $state -From $nameId -To $remoteId -Kind resolves-to
                    }
                    'CNAME' {
                        $nameId = & $ensureDnsName $item.Name $item.Source
                        $targetId = & $ensureDnsName $item.Data $item.Source
                        Add-NetworkGraphEdge -State $state -From $nameId -To $targetId -Kind resolves-to
                    }
                    'PTR' {
                        $nameId = & $ensureDnsName $item.Data $item.Source
                        $remoteId = & $ensureRemote $item.Query @{ RemoteHost = $item.Data } $item.Source
                        Add-NetworkGraphEdge -State $state -From $remoteId -To $nameId -Kind resolves-to
                    }
                    default { Write-Verbose "ConvertTo-NetworkGraph: $($item.Type) record for $($item.Name) has no node kind; skipped." }
                }
            }
            else {
                $type = $item.PSObject.TypeNames[0]
                $skipped[$type] = 1 + [int]$skipped[$type]
            }
        }
        foreach ($type in $skipped.Keys) { Write-Warning "ConvertTo-NetworkGraph skipped $($skipped[$type]) object(s) of type $type, which has no node kind." }

        # Trace hops, chained per target in hop order.
        foreach ($group in ($hops | Group-Object Target)) {
            $previous = & $ensureHost
            foreach ($hop in ($group.Group | Sort-Object Hop)) {
                $id = "hop/$($hop.Target)/$($hop.Hop)"
                $null = Add-NetworkGraphNode -State $state -Kind Hop -Id $id -Name ('{0} {1}' -f $hop.Hop, ($hop.Ip ? $hop.Ip : '*')) -Source $hop.Source -Property @{
                    Target = $hop.Target; Hop = $hop.Hop; Ip = $hop.Ip; RttMs = @($hop.RttMs); LossPercent = $hop.LossPercent
                }
                Add-NetworkGraphEdge -State $state -From $previous -To $id -Kind hops-to
                $previous = $id
            }
        }

        # Classify every remote address with the bundled data; link clouds and ASNs.
        $scopes = @{}
        foreach ($node in @($state.Nodes | Where-Object { $_.Kind -eq 'RemoteHost' -and $_.Ip })) {
            $info = Test-IPAddress -Address $node.Ip
            $scopes[$node.Ip] = $info
            foreach ($key in 'Cloud', 'Service', 'Asn', 'Owner') { if ($null -eq $node.$key -and $null -ne $info.$key) { $node.$key = $info.$key } }
            if ($node.Cloud) {
                $cloudId = "cloud/$($node.Cloud)"
                $null = Add-NetworkGraphNode -State $state -Kind Cloud -Id $cloudId -Name $node.Cloud -Source 'cloud-ranges.json.gz' -Property @{ Cloud = $node.Cloud }
                Add-NetworkGraphEdge -State $state -From $node.Id -To $cloudId -Kind belongs-to
            }
            if ($node.Asn) {
                $asnId = "AS$($node.Asn)"
                $null = Add-NetworkGraphNode -State $state -Kind Asn -Id $asnId -Name ($node.Owner ? "$asnId $($node.Owner)" : $asnId) -Source $node.Source -Property @{ Asn = $node.Asn; Owner = $node.Owner }
                Add-NetworkGraphEdge -State $state -From $node.Id -To $asnId -Kind belongs-to
            }
        }
        foreach ($node in @($state.Nodes | Where-Object { $_.Kind -eq 'Connection' -and $_.RemoteIp })) {
            $remote = $state.ById[(ConvertTo-NetworkGraphIpValue -Ip $node.RemoteIp -Unmap).Ip]
            $info = $scopes[$remote.Ip]
            if ($info -and $info.Scope -eq 'Public' -and -not $remote.Cloud) {
                & $addFinding 'NonCloudPublicConnection' $node.Id $remote.Id "$($node.Protocol) to $($remote.Ip) ($($remote.Name)) is a public address in no harvested cloud range."
            }
        }

        # Subnets: below the cloud minimum, and overlaps that are not a planned parent and child.
        $subnets = @($state.Nodes | Where-Object Kind -eq 'Subnet')
        $parentOf = @{}
        foreach ($edge in $state.Edges) {
            if ($edge.Kind -eq 'contains' -and $state.ById[$edge.From].Kind -eq 'Subnet' -and $state.ById[$edge.To].Kind -eq 'Subnet') { $parentOf[$edge.To] = $edge.From }
        }
        $isAncestor = {
            param($Ancestor, $Id)
            $seen = 0
            while ($parentOf.ContainsKey($Id) -and $seen -lt 256) { $Id = $parentOf[$Id]; if ($Id -eq $Ancestor) { return $true }; $seen++ }
            $false
        }
        $resolved = @{}
        foreach ($node in $subnets) {
            $resolved[$node.Id] = Resolve-NetworkGraphPrefix -Cidr $node.Cidr
            if ($node.BelowCloudMinimum) { & $addFinding 'BelowCloudMinimum' $node.Id $null "$($node.Cidr) is smaller than the $($node.Cloud) minimum subnet." }
        }
        for ($i = 0; $i -lt $subnets.Count; $i++) {
            for ($j = $i + 1; $j -lt $subnets.Count; $j++) {
                $a = $subnets[$i]; $b = $subnets[$j]
                $relation = Get-NetworkGraphPrefixRelation -Left $resolved[$a.Id] -Right $resolved[$b.Id]
                if ($relation -eq 'Disjoint' -or (& $isAncestor $a.Id $b.Id) -or (& $isAncestor $b.Id $a.Id)) { continue }
                & $addFinding 'SubnetOverlap' $a.Id $b.Id "$($a.Id) $relation $($b.Id)."
            }
        }

        [pscustomobject]@{
            PSTypeName = 'NetworkGraph.Graph'
            Root       = $state.ById.ContainsKey($hostId) ? $hostId : $null
            Nodes      = $state.Nodes.ToArray()
            Edges      = $state.Edges.ToArray()
            Findings   = $findings.ToArray()
        }
    }
}
