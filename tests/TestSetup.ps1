# Dot-sourced by every *.Tests.ps1 in BeforeAll. Imports the module from src and points the user
# data cache at an empty TestDrive folder, so tests read the bundled data and never the real
# $env:LOCALAPPDATA\NetworkGraph\data. Live tests (tag Live) run only with NETWORKGRAPH_LIVE=1.

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:ModuleRoot = Join-Path $script:RepoRoot 'src' 'Graph.Emitter.Network'
$script:Fixtures = Join-Path $PSScriptRoot 'fixtures'

Get-Module Graph.Emitter.Network | Remove-Module -Force
Import-Module (Join-Path $script:ModuleRoot 'Graph.Emitter.Network.psd1') -Force -ErrorAction Stop
$emptyUserRoot = Join-Path $TestDrive 'user-data'
InModuleScope Graph.Emitter.Network -Parameters @{ Root = $emptyUserRoot } {
    param($Root)
    $script:NetworkGraphDataUserRoot = $Root
    $script:NetworkGraphDataMemo = @{}
    $script:NetworkGraphNativeInvoker = $null
    $script:NetworkGraphWebInvoker = $null
    $script:NetworkGraphTcpConnector = $null
}

function Get-Fixture {
    param([Parameter(Mandatory)][string]$Name)
    [System.IO.File]::ReadAllText((Join-Path $script:Fixtures $Name))
}

function Get-FixtureJson {
    param([Parameter(Mandatory)][string]$Name)
    @(Get-Fixture $Name | ConvertFrom-Json)
}

# Makes every native command return fixture text (stdout) with exit code 0, keyed by the command
# name; a scriptblock value is called with the argument list and returns the text. -ExitCode and
# -ErrorText (stderr) override per command. Records each call in $script:NativeCalls. No real
# tool runs.
function Set-NativeFixture {
    param([Parameter(Mandatory)][hashtable]$Output, [hashtable]$ExitCode = @{}, [hashtable]$ErrorText = @{})
    $script:NativeCalls = [System.Collections.Generic.List[object]]::new()
    $calls = $script:NativeCalls
    InModuleScope Graph.Emitter.Network -Parameters @{ Output = $Output; ExitCode = $ExitCode; ErrorText = $ErrorText; Calls = $calls } {
        param($Output, $ExitCode, $ErrorText, $Calls)
        $script:NetworkGraphNativeInvoker = {
            param($FilePath, $ArgumentList)
            $Calls.Add([pscustomobject]@{ FilePath = $FilePath; ArgumentList = $ArgumentList })
            $text = $Output[$FilePath]
            if ($text -is [scriptblock]) { $text = & $text $ArgumentList }
            [pscustomobject]@{ ExitCode = $ExitCode[$FilePath] ?? 0; Output = $text; Error = $ErrorText[$FilePath] ?? ''; TimedOut = $false }
        }.GetNewClosure()
    }
}

# Makes every HTTP request return the text in -Content keyed by URL (a scriptblock value is
# called with the URL; a missing URL throws, as a failed request does).
function Set-WebFixture {
    param([Parameter(Mandatory)][hashtable]$Content)
    InModuleScope Graph.Emitter.Network -Parameters @{ Content = $Content } {
        param($Content)
        $script:NetworkGraphWebInvoker = {
            param($Uri)
            if (-not $Content.ContainsKey($Uri)) { throw "No fixture for $Uri" }
            $text = $Content[$Uri]
            if ($text -is [scriptblock]) { $text = & $text $Uri }
            [pscustomobject]@{ Uri = $Uri; StatusCode = 200; Content = $text }
        }.GetNewClosure()
    }
}

# Offline input for ConvertTo-NetworkGraph with every node kind: a Linux host built from the
# ip fixtures, ss connections, a tracert, neighbours, DNS records, an external address, an Azure
# address, a subnet plan and two loose subnets (one below the Azure minimum, one overlapping).
function Get-TestGraphInput {
    $typed = {
        param($Row, $Type, $Source)
        $Row.PSObject.TypeNames.Insert(0, $Type)
        if ($Source -and -not $Row.PSObject.Properties['Source']) { $Row | Add-Member Source $Source }
        $Row
    }
    $interfaces = InModuleScope Graph.Emitter.Network -Parameters @{ A = (Get-Fixture 'ip-addr.linux.json'); R = (Get-Fixture 'ip-route.linux.json'); D = (Get-Fixture 'resolv.conf.linux.txt') } {
        param($A, $R, $D) ConvertFrom-NetworkGraphIpAddrJson -Text $A -RouteText $R -ResolvConf $D
    }
    $interfaces = foreach ($row in $interfaces) {
        [pscustomobject]@{ PSTypeName = 'NetworkGraph.Interface'; Name = $row.Name; InterfaceKey = $row.InterfaceKey; Description = $row.Description; Status = $row.Status; Ip = $row.Ip; PrefixLength = $row.PrefixLength; MacAddress = $row.MacAddress; Vendor = $null; Gateway = $row.Gateway; Dns = $row.Dns; Source = 'ip -j addr' }
    }
    $keys = Get-TestKeyMap -Platform Linux
    $routes = foreach ($row in InModuleScope Graph.Emitter.Network -Parameters @{ T = (Get-Fixture 'ip-route.linux.json'); K = $keys } { param($T, $K) ConvertFrom-NetworkGraphIpRouteJson -Text $T -KeyMap $K }) {
        & $typed $row 'NetworkGraph.Route' 'ip -j route show table main; Get-Content /sys/class/net/*/ifindex'
    }
    $orphan = InModuleScope Graph.Emitter.Network { New-NetworkGraphRouteRow -Cidr '10.99.0.0/16' -NextHop '172.17.0.254' }
    $routes = @($routes) + (& $typed $orphan 'NetworkGraph.Route' 'fixture')
    $hostRow = [pscustomobject]@{ PSTypeName = 'NetworkGraph.Host'; HostName = 'testhost'; Os = 'Ubuntu 22.04.4 LTS'; Platform = 'Linux'; Interfaces = @($interfaces); Routes = @($routes); Source = 'fixture' }

    $connections = foreach ($row in InModuleScope Graph.Emitter.Network -Parameters @{ T = (Get-Fixture 'ss.linux.txt') } { param($T) ConvertFrom-NetworkGraphSsOutput -Text $T }) { & $typed $row 'NetworkGraph.Connection' 'ss -tunap' }
    $hops = foreach ($row in InModuleScope Graph.Emitter.Network -Parameters @{ T = (Get-Fixture 'tracert.windows.txt') } { param($T) ConvertFrom-NetworkGraphTracertOutput -Text $T }) {
        $row | Add-Member Target '1.1.1.1'
        & $typed $row 'NetworkGraph.Hop' 'tracert -d -h 12 -w 2000 1.1.1.1'
    }
    $neighbors = [pscustomobject]@{ PSTypeName = 'NetworkGraph.Neighbor'; Ip = '172.17.0.1'; MacAddress = '76-7E-57-00-00-21'; Vendor = $null; State = 'Reachable'; Interface = 'eth0'; InterfaceKey = '2'; Source = 'ip -j neigh; Get-Content /sys/class/net/*/ifindex' }
    $dns = foreach ($row in InModuleScope Graph.Emitter.Network -Parameters @{ T = (Get-Fixture 'dig.linux.txt') } { param($T) ConvertFrom-NetworkGraphDigOutput -Text $T }) {
        $row | Add-Member Query (($row.Type -eq 'PTR') ? '1.1.1.1' : $row.Name)
        & $typed $row 'NetworkGraph.DnsRecord' 'dig +noall +answer'
    }
    $external = [pscustomobject]@{ PSTypeName = 'NetworkGraph.ExternalIp'; Ip = '203.0.113.7'; Asn = 64496; Owner = 'Example Networks'; Source = 'fixture' }
    $azure = $null
    $prefixes = (Get-NetworkGraphData -Kind CloudRanges).Data['prefixes']
    $azureKey = $prefixes.Keys | Where-Object { -not $_.Contains(':') -and @($prefixes[$_])[0][0] -eq 'Azure' } | Select-Object -First 1
    $azure = Test-IPAddress ($azureKey.Split('/')[0])
    $plan = New-SubnetPlan 10.0.0.0/22 -Hosts 250, 120 -Cloud Azure
    $loose = @(Get-Subnet 10.0.0.0/30 -Cloud Azure -WarningAction SilentlyContinue; Get-Subnet 10.0.0.128/25 -Cloud Azure)
    $port = [pscustomobject]@{ PSTypeName = 'NetworkGraph.Port'; Target = 'one.one.one.one'; Ip = '1.1.1.1'; Port = 443; Protocol = 'Tcp'; Open = $true; Service = 'https'; LatencyMs = 12; Source = 'fixture' }

    @($hostRow) + @($connections) + @($hops) + @($neighbors) + @($dns) + @($external) + @($azure) + @($plan) + $loose + @($port)
}

# The interface key lookup (Get-NetworkGraphInterfaceKeyMap) as it reads on each platform:
# Windows from tests/fixtures/NetworkInterface.windows.json, captured with the other Windows
# fixtures; Linux from the ip -j addr capture (ifindex by ifname, as /sys/class/net reports it).
function Get-TestKeyMap {
    param([Parameter(Mandatory)][ValidateSet('Windows', 'Linux')][string]$Platform)
    if ($Platform -eq 'Windows') {
        return InModuleScope Graph.Emitter.Network -Parameters @{ O = (Get-FixtureJson 'NetworkInterface.windows.json') } { param($O) Get-NetworkGraphInterfaceKeyMap -InputObject $O -Platform Windows }
    }
    $map = [pscustomobject]@{ ByIndex = @{}; ByName = @{}; Source = 'Get-Content /sys/class/net/*/ifindex' }
    foreach ($link in @(Get-Fixture 'ip-addr.linux.json' | ConvertFrom-Json)) { $map.ByIndex["$($link.ifindex)"] = "$($link.ifindex)"; $map.ByName[$link.ifname] = "$($link.ifindex)" }
    $map
}

function Clear-NativeFixture {
    InModuleScope Graph.Emitter.Network { $script:NetworkGraphNativeInvoker = $null; $script:NetworkGraphWebInvoker = $null }
}
