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
        TerraformGraph uses (Id, Kind first; edges From, To, Kind, then Source); docs/graph-shape.md
        is the contract. Offline: remote addresses are classified with the bundled data (Test-IPAddress),
        nothing is looked up on the network.

        Node kinds and Ids: Host <hostname>; Interface <host>/if/<InterfaceKey> (the interface
        GUID on Windows, the ifindex on Linux, so renaming an adapter keeps its node; a row with no
        key, and no Interface row with the same name in the input to borrow one from, falls back to
        <host>/if/<name>); Subnet <cidr>@<cloud>; Route
        <host>/route/<cidr>/<next hop or on-link>/<InterfaceKey, else interface name, else ->; Hop
        hop/<target>/<tool>/<n>;
        Connection <host>/conn/<protocol>/<local ip>:<port>/<remote ip>:<port>[/<pid>] (IPv6 in
        [brackets], remote * for a listener, /<pid> when the process is known); Process
        <host>:<pid>; RemoteHost <ip>, or dns:<name> for a DNS name; Cloud cloud/<cloud>;
        Asn AS<number>. Observed rows belong to -HostName (default this computer) unless a
        Get-NetworkHost object names the host.

        Edge kinds: Contains (host to interface, process, connection and route; interface to
        route; subnet to interface and to planned subnet), RoutesTo (route to next hop; host to
        its external address), HopsTo (host to first hop, hop to hop), ConnectsTo (connection to
        remote host; interface to neighbour), OwnedBy (connection to process), ResolvesTo (DNS
        name to address or name), BelongsTo (remote host to cloud and to ASN). Every edge has the
        Source of the row that asserted it; the first row to assert an edge keeps it.

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
        Kind, Source), Findings (NetworkGraph.Finding: Finding, NodeId, RelatedId, Detail), and the script
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
        # Rows that crossed a process boundary (Invoke-Command, a job) carry 'Deserialized.<type>'.
        $is = { param($Item, $Type) ($Item.PSObject.TypeNames -replace '^(Deserialized\.)+', '') -contains $Type }

        $hostItem = $items | Where-Object { & $is $_ 'NetworkGraph.Host' } | Select-Object -First 1
        if ($hostItem) { $HostName = $hostItem.HostName }
        $hostId = $HostName.ToLowerInvariant()
        # The Source an edge carries: the Source of the row that asserted it. A row built by hand
        # with no Source still gives its edges a non-empty one, naming the row's type.
        $sourceOf = { param($Item) $Item.Source ? [string]$Item.Source : "$($Item.PSObject.TypeNames[0]) (no Source)" }
        $ensureHost = {
            Add-NetworkGraphNode -State $state -Kind Host -Id $hostId -Name $HostName -Property @{ HostName = $HostName } | Out-Null
            $hostId
        }
        # The interface key a row carries, else the key an Interface row with the same name carries
        # in this input (a route or neighbour row from 0.1.x, or one whose tool gave no index).
        $interfaceKeys = @{}
        $keyOf = {
            param($Name, $Key)
            if ($Key) { return [string]$Key }
            if ($Name -and $interfaceKeys.ContainsKey($Name)) { return $interfaceKeys[$Name] }
            $null
        }
        $ensureInterface = {
            param($Name, $Key, $Source, $EdgeSource)
            $key = & $keyOf $Name $Key
            $id = "$(& $ensureHost)/if/$($key ? $key : $Name)"
            $null = Add-NetworkGraphNode -State $state -Kind Interface -Id $id -Name $Name -Source $Source -Property @{ InterfaceName = $Name; InterfaceKey = $key }
            Add-NetworkGraphEdge -State $state -From $hostId -To $id -Kind Contains -Source $EdgeSource
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
        # A calculated subnet's Source is the command that recalculates it, citing the cloud's
        # reservation rules when a cloud applies.
        $subnetSource = {
            param($Cidr, $Cloud, $Note)
            $cite = ($Cloud -and $Cloud -ne 'None') ? (Get-NetworkGraphDataCitation -Kind CloudReservations -Cloud $Cloud) : $null
            $comment = @($Note, $cite) | Where-Object { $_ }
            "Get-Subnet $Cidr -Cloud $($Cloud ? $Cloud : 'None')" + ($comment ? "  # $($comment -join '; ')" : '')
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
        foreach ($item in $queue) {
            if ((& $is $item 'NetworkGraph.Interface') -and $item.Name -and $item.InterfaceKey -and -not $interfaceKeys.ContainsKey($item.Name)) {
                $interfaceKeys[$item.Name] = [string]$item.InterfaceKey
            }
        }

        $hops = [System.Collections.Generic.List[object]]::new()
        $skipped = @{}
        foreach ($item in $queue) {
            if (& $is $item 'NetworkGraph.Subnet') {
                $id = & $ensureSubnet $item.Cidr $item.Cloud (& $subnetSource $item.Cidr $item.Cloud $null)
                if (& $is $item 'NetworkGraph.PlannedSubnet') {
                    $node = $state.ById[$id]
                    $node.Name = "$($item.Name) $($item.Cidr)"
                    $node.Source = & $subnetSource $item.Cidr $item.Cloud "planned in $($item.Parent) by New-SubnetPlan"
                    $parentId = & $ensureSubnet $item.Parent $item.Cloud (& $subnetSource $item.Parent $item.Cloud 'parent of a New-SubnetPlan plan')
                    Add-NetworkGraphEdge -State $state -From $parentId -To $id -Kind Contains -Source $node.Source
                }
            }
            elseif (& $is $item 'NetworkGraph.Interface') {
                $rowSource = & $sourceOf $item
                $id = & $ensureInterface $item.Name $item.InterfaceKey $item.Source $rowSource
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
                    Add-NetworkGraphEdge -State $state -From $subnetId -To $id -Kind Contains -Source $rowSource
                }
            }
            elseif (& $is $item 'NetworkGraph.Route') {
                $owner = & $ensureHost
                $rowSource = & $sourceOf $item
                $key = & $keyOf $item.Interface $item.InterfaceKey
                $via = $key ? $key : ($item.Interface ? $item.Interface : '-')
                $id = "$owner/route/$($item.Cidr)/$($item.NextHop ? $item.NextHop : 'on-link')/$via"
                $null = Add-NetworkGraphNode -State $state -Kind Route -Id $id -Name $item.Cidr -Source $item.Source -Property @{
                    Destination = $item.Destination; PrefixLength = $item.PrefixLength; NextHop = $item.NextHop; InterfaceName = $item.Interface; InterfaceKey = $key; Metric = $item.Metric
                }
                if ($item.Interface -or $key) {
                    $interfaceId = & $ensureInterface $item.Interface $key $item.Source $rowSource
                    Add-NetworkGraphEdge -State $state -From $interfaceId -To $id -Kind Contains -Source $rowSource
                }
                else {
                    Add-NetworkGraphEdge -State $state -From $owner -To $id -Kind Contains -Source $rowSource
                    & $addFinding 'RouteWithoutInterface' $id $null "Route to $($item.Cidr) names no interface."
                }
                if ($item.NextHop) {
                    $remoteId = & $ensureRemote $item.NextHop $null $item.Source
                    Add-NetworkGraphEdge -State $state -From $id -To $remoteId -Kind RoutesTo -Source $rowSource
                }
            }
            elseif (& $is $item 'NetworkGraph.Connection') {
                $owner = & $ensureHost
                $rowSource = & $sourceOf $item
                $endpoint = { param($Ip, $Port) ($Ip.Contains(':') ? "[$Ip]" : $Ip) + ":$Port" }
                $local = & $endpoint $item.LocalIp $item.LocalPort
                $remote = $item.RemoteIp ? (& $endpoint $item.RemoteIp $item.RemotePort) : '*'
                # The PID is part of the Id: sockets that share an endpoint (SO_REUSEADDR, for
                # example several processes on UDP 0.0.0.0:5353) are separate connections.
                $id = "$owner/conn/$($item.Protocol.ToLowerInvariant())/$local/$remote" + (($null -ne $item.ProcessId) ? "/$($item.ProcessId)" : '')
                $null = Add-NetworkGraphNode -State $state -Kind Connection -Id $id -Name "$($item.Protocol) $local -> $remote" -Source $item.Source -Property @{
                    Protocol = $item.Protocol; LocalIp = $item.LocalIp; LocalPort = $item.LocalPort; RemoteIp = $item.RemoteIp; RemotePort = $item.RemotePort; State = $item.State; ProcessId = $item.ProcessId
                }
                Add-NetworkGraphEdge -State $state -From $owner -To $id -Kind Contains -Source $rowSource
                if ($null -ne $item.ProcessId) {
                    $processId = "${owner}:$($item.ProcessId)"
                    $null = Add-NetworkGraphNode -State $state -Kind Process -Id $processId -Name ($item.ProcessName ? $item.ProcessName : "$($item.ProcessId)") -Source $item.Source -Property @{
                        ProcessId = $item.ProcessId; ProcessName = $item.ProcessName
                    }
                    Add-NetworkGraphEdge -State $state -From $owner -To $processId -Kind Contains -Source $rowSource
                    Add-NetworkGraphEdge -State $state -From $id -To $processId -Kind OwnedBy -Source $rowSource
                }
                if ($item.RemoteIp) {
                    $extra = @{}
                    foreach ($key in 'RemoteHost', 'Cloud', 'Service', 'Asn', 'Owner') { if ($item.PSObject.Properties[$key]) { $extra[$key] = $item.$key } }
                    $remoteId = & $ensureRemote $item.RemoteIp $extra $item.Source
                    Add-NetworkGraphEdge -State $state -From $id -To $remoteId -Kind ConnectsTo -Source $rowSource
                }
                if ($item.Protocol -eq 'Tcp' -and $item.State -eq 'Listen' -and $item.LocalIp -in '0.0.0.0', '::') {
                    $who = $item.ProcessName ? " ($($item.ProcessName))" : ''
                    & $addFinding 'WildcardListener' $id $null "TCP port $($item.LocalPort) listens on every address ($($item.LocalIp))$who."
                }
            }
            elseif (& $is $item 'NetworkGraph.Neighbor') {
                $remoteId = & $ensureRemote $item.Ip @{ MacAddress = $item.MacAddress; Vendor = $item.Vendor } $item.Source
                if ($item.Interface -or $item.InterfaceKey) {
                    $rowSource = & $sourceOf $item
                    $interfaceId = & $ensureInterface $item.Interface $item.InterfaceKey $item.Source $rowSource
                    Add-NetworkGraphEdge -State $state -From $interfaceId -To $remoteId -Kind ConnectsTo -Source $rowSource
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
                Add-NetworkGraphEdge -State $state -From (& $ensureHost) -To $remoteId -Kind RoutesTo -Source (& $sourceOf $item)
            }
            elseif (& $is $item 'NetworkGraph.DnsRecord') {
                $rowSource = & $sourceOf $item
                switch ($item.Type) {
                    { $_ -in 'A', 'AAAA' } {
                        $nameId = & $ensureDnsName $item.Name $item.Source
                        $remoteId = & $ensureRemote $item.Data @{ RemoteHost = $item.Name } $item.Source
                        Add-NetworkGraphEdge -State $state -From $nameId -To $remoteId -Kind ResolvesTo -Source $rowSource
                    }
                    'CNAME' {
                        $nameId = & $ensureDnsName $item.Name $item.Source
                        $targetId = & $ensureDnsName $item.Data $item.Source
                        Add-NetworkGraphEdge -State $state -From $nameId -To $targetId -Kind ResolvesTo -Source $rowSource
                    }
                    'PTR' {
                        $nameId = & $ensureDnsName $item.Data $item.Source
                        $remoteId = & $ensureRemote $item.Query @{ RemoteHost = $item.Data } $item.Source
                        Add-NetworkGraphEdge -State $state -From $remoteId -To $nameId -Kind ResolvesTo -Source $rowSource
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

        # Trace hops, one chain per target and tool in hop order, so a native and a .NET trace of
        # the same target stay two chains. A row without Tool takes the first word of its Source.
        $toolOf = {
            param($Hop)
            if ($Hop.PSObject.Properties['Tool'] -and $Hop.Tool) { return [string]$Hop.Tool }
            $first = ([string]$Hop.Source -split '\s+')[0]
            ($first -match '^[A-Za-z][\w-]*$') ? $first : 'unknown'
        }
        foreach ($group in ($hops | Group-Object { "$($_.Target)|$(& $toolOf $_)" })) {
            $previous = & $ensureHost
            foreach ($hop in ($group.Group | Sort-Object Hop)) {
                $id = "hop/$($hop.Target)/$(& $toolOf $hop)/$($hop.Hop)"
                $responded = $hop.PSObject.Properties['Responded'] ? [bool]$hop.Responded : [bool]($hop.Ip -or @($hop.RttMs).Count)
                $null = Add-NetworkGraphNode -State $state -Kind Hop -Id $id -Name ('{0} {1}' -f $hop.Hop, ($hop.Ip ? $hop.Ip : '*')) -Source $hop.Source -Property @{
                    Target = $hop.Target; Hop = $hop.Hop; Ip = $hop.Ip; RttMs = @($hop.RttMs); AvgMs = $hop.PSObject.Properties['AvgMs'] ? $hop.AvgMs : $null
                    LossPercent = $hop.LossPercent; Responded = $responded
                }
                Add-NetworkGraphEdge -State $state -From $previous -To $id -Kind HopsTo -Source (& $sourceOf $hop)
                $previous = $id
            }
        }

        # Classify every remote address with the bundled data; link clouds and ASNs.
        $scopes = @{}
        foreach ($node in @($state.Nodes | Where-Object { $_.Kind -eq 'RemoteHost' -and $_.Ip })) {
            $info = Test-IPAddress -Address $node.Ip
            $scopes[$node.Ip] = $info
            $classified = "Test-IPAddress $($node.Ip)"
            $cloudSource = ($null -ne $node.Cloud -and $node.Source) ? $node.Source : $classified
            $asnSource = ($null -ne $node.Asn -and $node.Source) ? $node.Source : $classified
            foreach ($key in 'Cloud', 'Service', 'Asn', 'Owner') { if ($null -eq $node.$key -and $null -ne $info.$key) { $node.$key = $info.$key } }
            if ($node.Cloud) {
                $cloudId = "cloud/$($node.Cloud)"
                $null = Add-NetworkGraphNode -State $state -Kind Cloud -Id $cloudId -Name $node.Cloud -Source (Get-NetworkGraphDataCitation -Kind CloudRanges -Cloud $node.Cloud) -Property @{ Cloud = $node.Cloud }
                Add-NetworkGraphEdge -State $state -From $node.Id -To $cloudId -Kind BelongsTo -Source $cloudSource
            }
            if ($node.Asn) {
                $asnId = "AS$($node.Asn)"
                $null = Add-NetworkGraphNode -State $state -Kind Asn -Id $asnId -Name ($node.Owner ? "$asnId $($node.Owner)" : $asnId) -Source $node.Source -Property @{ Asn = $node.Asn; Owner = $node.Owner }
                Add-NetworkGraphEdge -State $state -From $node.Id -To $asnId -Kind BelongsTo -Source $asnSource
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
            if ($edge.Kind -eq 'Contains' -and $state.ById[$edge.From].Kind -eq 'Subnet' -and $state.ById[$edge.To].Kind -eq 'Subnet') { $parentOf[$edge.To] = $edge.From }
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
