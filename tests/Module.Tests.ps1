BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:PublicFiles = @(Get-ChildItem -Path (Join-Path $ModuleRoot 'Public') -Filter '*.ps1')
    $script:Manifest = Import-PowerShellDataFile -Path (Join-Path $ModuleRoot 'NetworkGraph.psd1')
}

Describe 'Module' {
    It 'is version 0.1.1 and needs PowerShell 7.4' {
        $Manifest.ModuleVersion | Should -Be '0.1.1'
        $Manifest.PowerShellVersion | Should -Be '7.4'
    }

    It 'every Public file exports exactly its function name' {
        foreach ($file in $PublicFiles) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
            $functions.Count | Should -Be 1 -Because "$($file.Name) holds one function"
            $functions[0].Name | Should -BeExactly $file.BaseName
        }
    }

    It 'every Private file defines exactly one function named for the file' {
        foreach ($file in Get-ChildItem -Path (Join-Path $ModuleRoot 'Private') -Filter '*.ps1') {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
            $functions.Count | Should -Be 1 -Because "$($file.Name) holds one helper"
            $functions[0].Name | Should -BeExactly $file.BaseName
        }
    }

    It 'psd1 exports match Public/' {
        @($Manifest.FunctionsToExport | Sort-Object) | Should -Be @($PublicFiles.BaseName | Sort-Object)
        @((Get-Module NetworkGraph).ExportedFunctions.Keys | Sort-Object) | Should -Be @($PublicFiles.BaseName | Sort-Object)
    }

    It 'exports 23 functions in three groups by noun' {
        $names = $Manifest.FunctionsToExport
        $names.Count | Should -Be 23
        @($names | Where-Object { $_ -match '-(Subnet|SubnetMask|SubnetPlan|SubnetOverlap|SubnetParent|SubnetChildren|IPAddress|MacAddressVendor)$' }).Count | Should -Be 9
        @($names | Where-Object { $_ -match '-(Network(Path|Port|Connection|Neighbor|Route|Interface|Name|Host|Scan)|ExternalIpAddress)$' }).Count | Should -Be 11
        @($names | Where-Object { $_ -match '-NetworkGraph(Data)?$' }).Count | Should -Be 3
    }

    It 'warns once at import on macOS that it is untested, and not on Windows or Linux' {
        $warnings = InModuleScope NetworkGraph {
            $saved = $script:NetworkGraphPlatform
            try {
                foreach ($platform in 'macOS', 'Windows', 'Linux') {
                    $script:NetworkGraphPlatform = $platform
                    Write-NetworkGraphPlatformWarning 3>&1 | ForEach-Object { "${platform}: $_" }
                }
            }
            finally { $script:NetworkGraphPlatform = $saved }
        }
        @($warnings).Count | Should -Be 1
        $warnings | Should -BeLike 'macOS: NetworkGraph is untested on macOS*'
        (Get-Content -Raw (Join-Path $ModuleRoot 'NetworkGraph.psm1')) | Should -Match '(?m)^Write-NetworkGraphPlatformWarning\s*$'
    }

    It 'ships no binaries' {
        @(Get-ChildItem -Path $RepoRoot -Recurse -File -Include '*.dll', '*.exe', '*.so', '*.dylib', '*.cs' |
                Where-Object FullName -notmatch '[\\/](\.git|dist)[\\/]').Count | Should -Be 0
    }

    It 'LICENSE is the Apache License 2.0: its first non-blank line contains "Apache License"' {
        # The apache.org text is kept verbatim, and it opens with a blank line.
        $first = @(Get-Content -Path (Join-Path $RepoRoot 'LICENSE') | Where-Object { $_.Trim() })[0]
        $first | Should -BeLike '*Apache License*'
        Get-Content -Raw (Join-Path $RepoRoot 'NOTICE') | Should -BeLike '*Copyright 2026 Jerry Balmer*'
        $Manifest.Copyright | Should -BeLike '*Apache License, Version 2.0*'
    }

    It 'psd1 LicenseUri resolves to a tracked file' -Skip:(-not (Test-Path (Join-Path (Split-Path -Parent $PSScriptRoot) '.git'))) {
        $data = $Manifest.PrivateData.PSData
        $prefix = "$($data.ProjectUri)/blob/main/"
        $data.LicenseUri | Should -BeLike "$prefix*"
        $relative = $data.LicenseUri.Substring($prefix.Length)
        Test-Path -LiteralPath (Join-Path $RepoRoot $relative) -PathType Leaf | Should -BeTrue
        @(git -C $RepoRoot ls-files -- $relative) | Should -Be @($relative)
    }

    It 'has comment-based help with a synopsis and an example for every exported function' {
        foreach ($name in $Manifest.FunctionsToExport) {
            $help = Get-Help $name -Full
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because $name
            @($help.Examples.Example).Count | Should -BeGreaterThan 0 -Because $name
        }
    }
}

Describe 'Argument completion' {
    BeforeAll {
        function Get-Completion([string]$Line) {
            @((TabExpansion2 -inputScript $Line -cursorColumn $Line.Length).CompletionMatches.CompletionText)
        }
    }

    It 'completes -Cloud on Get-Subnet' {
        Get-Completion 'Get-Subnet 10.0.0.0/24 -Cloud ' | Should -Be @('AWS', 'Azure', 'GCP', 'None')
        Get-Completion 'Get-Subnet 10.0.0.0/24 -Cloud A' | Should -Be @('AWS', 'Azure')
    }

    It 'completes -Cloud on New-SubnetPlan' {
        Get-Completion 'New-SubnetPlan 10.0.0.0/22 -Hosts 10 -Cloud G' | Should -Be @('GCP')
    }

    It 'completes -Tool on every observe command' {
        foreach ($command in 'Test-NetworkPath', 'Trace-NetworkPath', 'Test-NetworkPort', 'Get-NetworkConnection', 'Get-NetworkNeighbor', 'Get-NetworkRoute', 'Get-NetworkInterface', 'Resolve-NetworkName', 'Get-ExternalIpAddress', 'Get-NetworkHost', 'Invoke-NetworkScan') {
            Get-Completion "$command -Tool " | Should -Be @('Auto', 'DotNet', 'Native') -Because $command
        }
        Get-Completion 'Trace-NetworkPath 1.1.1.1 -Tool D' | Should -Be @('DotNet')
    }

    It 'completes -Protocol, -Type, -NativeTool and -State' {
        Get-Completion 'Test-NetworkPort x -Port 1 -Protocol ' | Should -Be @('Tcp', 'Udp')
        Get-Completion 'Resolve-NetworkName x -Type M' | Should -Be @('MX')
        Get-Completion 'Trace-NetworkPath x -NativeTool t' | Should -Be @('traceroute', 'tracert')
        Get-Completion 'Get-NetworkConnection -State Est' | Should -Be @('Established')
    }

    It 'completes data kinds on Get-NetworkGraphData and Update-NetworkGraphData' {
        Get-Completion 'Get-NetworkGraphData -Kind ' | Should -Be @('CloudRanges', 'CloudReservations', 'IpSources', 'Oui', 'Ports', 'SpecialUse')
        Get-Completion 'Update-NetworkGraphData -Kind ' | Should -Be @('CloudRanges', 'Oui', 'Ports', 'SpecialUse')
    }

    It 'completes Invoke-Build task names from .build.ps1, as TerraformGraph does' -Skip:(-not (Get-Module -ListAvailable InvokeBuild)) {
        # The completers register when .build.ps1 first runs in a session (Invoke-Build ?? lists
        # the tasks without running any), as in TerraformGraph. A fresh process keeps this run's
        # completers out of the test session.
        $script = "Set-Location '$RepoRoot'; `$null = Invoke-Build ??; foreach (`$line in 'Invoke-Build ', 'Invoke-Build -Task C', 'Invoke-Build Up') { ((TabExpansion2 -inputScript `$line -cursorColumn `$line.Length).CompletionMatches.CompletionText) -join ',' }"
        $lines = @(pwsh -NoProfile -Command $script)
        $lines[0] -split ',' | Should -Be @('RemoveModule', 'ImportModule', 'Test', 'Analyze', 'Assemble', 'UpdateData', 'CheckData', '.')
        $lines[1] | Should -Be 'CheckData'
        $lines[2] | Should -Be 'UpdateData'
    }
}

Describe 'Fixture scrubbing (CLAUDE.md, "Fixture scrub rule")' {
    BeforeAll {
        $script:FixtureFiles = @(Get-ChildItem -Path $Fixtures -File)
        # The capturing host's registry network: rdap-arin.json was captured for the host's own
        # external address, so the address it was queried for must now be a documentation
        # address, and no other fixture may hold any address in the network the registry returned.
        $rdap = Get-Fixture 'rdap-arin.json' | ConvertFrom-Json -AsHashtable
        $script:RdapQueried = @($rdap['links'] | ForEach-Object { ($_['value'] -split '/ip/')[-1] } | Select-Object -Unique)
        $script:HostNetwork = InModuleScope NetworkGraph -Parameters @{ Start = $rdap['startAddress']; End = $rdap['endAddress'] } {
            param($Start, $End)
            [pscustomobject]@{ First = (ConvertTo-NetworkGraphIpValue -Ip $Start).Value; Last = (ConvertTo-NetworkGraphIpValue -Ip $End).Value }
        }
    }

    It 'no fixture file contains the capturing host''s external address (read from rdap-arin.json)' {
        $RdapQueried.Count | Should -Be 1
        (Test-IPAddress $RdapQueried[0]).IsDocumentation | Should -BeTrue -Because 'the host address in rdap-arin.json is replaced with an RFC 5737 / 3849 address'
        foreach ($file in $FixtureFiles | Where-Object Name -ne 'rdap-arin.json') {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            foreach ($match in [regex]::Matches($text, '(?<![\d.])\d{1,3}(?:\.\d{1,3}){3}(?![\d.])')) {
                $ip = $null
                if (-not [System.Net.IPAddress]::TryParse($match.Value, [ref]$ip)) { continue }
                $value = InModuleScope NetworkGraph -Parameters @{ Ip = $match.Value } { param($Ip) (ConvertTo-NetworkGraphIpValue -Ip $Ip).Value }
                ($value -ge $HostNetwork.First -and $value -le $HostNetwork.Last) | Should -BeFalse -Because "$($file.Name) holds $($match.Value), inside the capturing host's network"
            }
        }
    }

    It 'no fixture contains the capturing site''s ISP infrastructure (the record of what was scrubbed in 0.1.1)' {
        # Replaced in 0.1.1 (CLAUDE.md, fixture scrub rule): the ISP's resolvers and resolver name,
        # the first public hops after the gateway, and a Wi-Fi adapter named for its device model.
        $scrubbed = @(
            '68.105.28.11', '68.105.28.12', '68.105.29.11', 'doh.cox.net'
            '68.1.0.191', '184.183.131.9'
            'Killer(R) Wi-Fi 6E AX1675x 160MHz Wireless Network Adapter (210NGW)', 'AX1675x', '210NGW'
        )
        foreach ($file in $FixtureFiles) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            foreach ($literal in $scrubbed) { $text.Contains($literal) | Should -BeFalse -Because "$($file.Name) holds '$literal'" }
        }
    }

    It 'no fixture host name ends in a residential ISP''s domain' {
        $isp = '(?i)\b[a-z0-9-]+(\.[a-z0-9-]+)*\.(cox\.net|comcast\.net|att\.net|charter\.com|centurylink\.net|verizon\.net|spectrum\.com)\b'
        foreach ($file in $FixtureFiles) {
            $match = [regex]::Match([System.IO.File]::ReadAllText($file.FullName), $isp)
            $match.Success | Should -BeFalse -Because "$($file.Name) holds '$($match.Value)'"
        }
    }

    It 'no fixture MAC has a device half other than 00-00-nn, in MAC form or inside an EUI-64 IPv6 address' {
        # Multicast and broadcast MACs (group bit set) and the all-zero MAC name no device. The OUI
        # test vectors live in Get-MacAddressVendor.Tests.ps1, not in fixtures.
        $mac = '(?<![0-9A-Fa-f:-])([0-9A-Fa-f]{2})([-:])([0-9A-Fa-f]{2})\2([0-9A-Fa-f]{2})\2([0-9A-Fa-f]{2})\2([0-9A-Fa-f]{2})\2([0-9A-Fa-f]{2})(?![0-9A-Fa-f:-])'
        foreach ($file in $FixtureFiles) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            foreach ($match in [regex]::Matches($text, $mac)) {
                $bytes = @(1, 3, 4, 5, 6, 7 | ForEach-Object { [Convert]::ToByte($match.Groups[$_].Value, 16) })
                if (($bytes[0] -band 1) -or -not ($bytes | Where-Object { $_ })) { continue }
                ($bytes[3] -eq 0 -and $bytes[4] -eq 0) | Should -BeTrue -Because "$($file.Name) holds $($match.Value)"
            }
            foreach ($match in [regex]::Matches($text, '(?<![0-9A-Fa-f:])[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){2,7}(?![0-9A-Fa-f:])')) {
                $ip = $null
                if (-not [System.Net.IPAddress]::TryParse($match.Value, [ref]$ip) -or $ip.AddressFamily -ne 'InterNetworkV6') { continue }
                $bytes = $ip.GetAddressBytes()
                if ($bytes[11] -ne 0xFF -or $bytes[12] -ne 0xFE) { continue }
                ($bytes[13] -eq 0 -and $bytes[14] -eq 0) | Should -BeTrue -Because "$($file.Name) holds $($match.Value), an EUI-64 address that carries a MAC"
            }
        }
    }
}

Describe 'Native results are checked in one place (Invoke-NetworkGraphNative -OkExitCodes)' {
    It 'every Invoke-NetworkGraphNative call declares -OkExitCodes' {
        $calls = foreach ($file in Get-ChildItem -Path $ModuleRoot -Recurse -Filter '*.ps1') {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-NetworkGraphNative' }, $true) |
                ForEach-Object { [pscustomobject]@{ File = $file.Name; Line = $_.Extent.StartLineNumber; Declares = [bool]($_.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'OkExitCodes' }) } }
        }
        @($calls).Count | Should -Be 19
        foreach ($call in $calls) { $call.Declares | Should -BeTrue -Because "$($call.File):$($call.Line)" }
    }

    It 'a timed-out tool throws with the command line and nothing is parsed' {
        InModuleScope NetworkGraph {
            $script:NetworkGraphNativeInvoker = { param($FilePath, $ArgumentList) [pscustomobject]@{ ExitCode = $null; Output = 'partial'; Error = ''; TimedOut = $true } }
            try { { Invoke-NetworkGraphNative -FilePath ss -ArgumentList '-tunap' -TimeoutSec 5 -OkExitCodes 0 } | Should -Throw '*timed out after 5 s*Command: ss -tunap*' }
            finally { $script:NetworkGraphNativeInvoker = $null }
        }
    }

    Context 'exit 2 with stderr text throws, naming both, for <Name>' -ForEach @(
        @{ Name = 'Test-NetworkPath (ping)'; Tool = 'ping'; Run = { Test-NetworkPath 192.0.2.1 -Count 1 -Tool Native -ErrorAction Stop } }
        @{ Name = 'Trace-NetworkPath (tracert)'; Tool = 'tracert'; Run = { Trace-NetworkPath 192.0.2.1 -NativeTool tracert -Tool Native } }
        @{ Name = 'Trace-NetworkPath (pathping)'; Tool = 'pathping'; Run = { Trace-NetworkPath 192.0.2.1 -NativeTool pathping -Tool Native } }
        @{ Name = 'Trace-NetworkPath (mtr)'; Tool = 'mtr'; Run = { Trace-NetworkPath 192.0.2.1 -NativeTool mtr -Tool Native } }
        @{ Name = 'Trace-NetworkPath (traceroute)'; Tool = 'traceroute'; Run = { Trace-NetworkPath 192.0.2.1 -NativeTool traceroute -Tool Native } }
        @{ Name = 'Test-NetworkPort (nc)'; Tool = 'nc'; Run = { Test-NetworkPort 192.0.2.1 -Port 80 -Tool Native -ErrorAction Stop } }
        @{ Name = 'Get-NetworkConnection (ss)'; Tool = 'ss'; Run = { Get-NetworkConnection -Tool Native } }
        @{ Name = 'Get-NetworkRoute (ip)'; Tool = 'ip'; Run = { Get-NetworkRoute -Tool Native } }
        @{ Name = 'Get-NetworkNeighbor (ip)'; Tool = 'ip'; Run = { Get-NetworkNeighbor -Tool Native } }
        @{ Name = 'Get-NetworkNeighbor (arp)'; Tool = 'arp'; Run = { Get-NetworkNeighbor -Tool Native } }
        @{ Name = 'Get-NetworkInterface (ip)'; Tool = 'ip'; Run = { Get-NetworkInterface -Tool Native } }
        @{ Name = 'Get-NetworkHost (ip, through Get-NetworkInterface)'; Tool = 'ip'; Run = { Get-NetworkHost -Tool Native } }
        @{ Name = 'Resolve-NetworkName (dig)'; Tool = 'dig'; Run = { Resolve-NetworkName example.com -Tool Native } }
        @{ Name = 'Resolve-NetworkName (nslookup)'; Tool = 'nslookup'; Run = { Resolve-NetworkName example.com -Tool Native } }
        @{ Name = 'Get-ExternalIpAddress (curl)'; Tool = 'curl'; Run = { Get-ExternalIpAddress -Tool Native } }
        @{ Name = 'Invoke-NetworkScan (nmap)'; Tool = 'nmap'; Run = { Invoke-NetworkScan 192.0.2.1 -Port 80 -Tool Native } }
    ) {
        BeforeAll {
            Mock Resolve-NetworkGraphTool -ModuleName NetworkGraph -MockWith ([scriptblock]::Create("'$Tool'"))
            Set-NativeFixture -Output @{ $Tool = '' } -ExitCode @{ $Tool = 2 } -ErrorText @{ $Tool = "simulated $Tool failure: bad option" }
        }
        AfterAll { Clear-NativeFixture }

        It 'throws with exit 2, the stderr text and the command line' {
            $message = try { & $Run | Out-Null; $null } catch { $_.Exception.Message }
            $message | Should -Not -BeNullOrEmpty
            $message | Should -BeLike "*exit code 2*"
            $message | Should -BeLike "*simulated $Tool failure: bad option*"
            $message | Should -BeLike "*Command: $Tool *"
        }
    }
}

Describe 'Text parsers refuse output they do not recognise' {
    BeforeAll {
        # The fixture cut to its header: everything before the first line that carries data.
        function Get-Header([string]$Name, [string]$UpTo) {
            $lines = (Get-Fixture $Name) -split "`r?`n"
            $index = 0
            while ($index -lt $lines.Count -and $lines[$index] -notmatch $UpTo) { $index++ }
            ($lines[0..([math]::Max(0, $index - 1))] -join "`n")
        }
    }

    It '<Parser> on <Fixture> cut to its header line throws "output not recognised (non-English locale?); use -Tool DotNet"' -ForEach @(
        @{ Parser = 'ConvertFrom-NetworkGraphPingOutput'; Fixture = 'ping.windows.txt'; UpTo = '^Reply from' }
        @{ Parser = 'ConvertFrom-NetworkGraphPingOutput'; Fixture = 'ping.linux.txt'; UpTo = 'bytes from' }
        @{ Parser = 'ConvertFrom-NetworkGraphTracertOutput'; Fixture = 'tracert.windows.txt'; UpTo = '^\s+1\s' }
        @{ Parser = 'ConvertFrom-NetworkGraphPathpingOutput'; Fixture = 'pathping.windows.txt'; UpTo = '^\s+0\s' }
        @{ Parser = 'ConvertFrom-NetworkGraphTracerouteOutput'; Fixture = 'traceroute.linux.txt'; UpTo = '^\s+1\s' }
        @{ Parser = 'ConvertFrom-NetworkGraphArpOutput'; Fixture = 'arp.windows.txt'; UpTo = '^\s+\d+\.' }
        @{ Parser = 'ConvertFrom-NetworkGraphNslookupOutput'; Fixture = 'nslookup.windows.txt'; UpTo = '^Name:' }
        @{ Parser = 'ConvertFrom-NetworkGraphNslookupOutput'; Fixture = 'nslookup.linux.txt'; UpTo = '^Name:' }
    ) {
        $header = Get-Header $Fixture $UpTo
        $header.Trim() | Should -Not -BeNullOrEmpty
        { InModuleScope NetworkGraph -Parameters @{ P = $Parser; T = $header } { param($P, $T) & $P -Text $T } } |
            Should -Throw '*output not recognised (non-English locale?); use -Tool DotNet*'
        # The whole fixture still parses.
        @(InModuleScope NetworkGraph -Parameters @{ P = $Parser; T = (Get-Fixture $Fixture) } { param($P, $T) & $P -Text $T }).Count | Should -BeGreaterThan 0
    }

    It 'dig: a fixture line cut to its first two fields throws; ss: a header with no sockets is a genuine empty table' {
        $digLine = ((Get-Fixture 'dig.linux.txt') -split "`r?`n")[0] -split '\s+' | Select-Object -First 2
        { InModuleScope NetworkGraph -Parameters @{ T = ($digLine -join "`t") } { param($T) ConvertFrom-NetworkGraphDigOutput -Text $T } } | Should -Throw '*dig output not recognised*'
        $ssHeader = ((Get-Fixture 'ss.linux.txt') -split "`r?`n")[0]
        @(InModuleScope NetworkGraph -Parameters @{ T = $ssHeader } { param($T) ConvertFrom-NetworkGraphSsOutput -Text $T }).Count | Should -Be 0
        $ssCut = (((Get-Fixture 'ss.linux.txt') -split "`r?`n")[1] -split '\s+' | Select-Object -First 3) -join ' '
        { InModuleScope NetworkGraph -Parameters @{ T = $ssCut } { param($T) ConvertFrom-NetworkGraphSsOutput -Text $T } } | Should -Throw '*ss output not recognised*'
    }

    It 'an exit code the caller declared as an answer (ping 1 = no reply) is not a parse failure' {
        $header = Get-Header 'ping.windows.txt' '^Reply from'
        { InModuleScope NetworkGraph -Parameters @{ T = $header } { param($T) ConvertFrom-NetworkGraphPingOutput -Text $T -ExitCode 1 } } | Should -Not -Throw
    }

    It 'native tools run with LC_ALL=C and LANG=C off Windows' -Skip:$IsWindows {
        # pwsh is the test runner itself, not a network tool.
        $run = InModuleScope NetworkGraph { Invoke-NetworkGraphNative -FilePath pwsh -ArgumentList '-NoProfile', '-Command', '"$env:LC_ALL|$env:LANG"' -OkExitCodes 0 }
        $run.Output.Trim() | Should -Be 'C|C'
    }
}

Describe 'Ontology' {
    It "resolves every term in ONTOLOGY.md's terminology table to an exported command, a typed object property or a data file" {
        $text = Get-Content -LiteralPath (Join-Path $RepoRoot 'ONTOLOGY.md') -Raw
        $section = [regex]::Match($text, '(?ms)^## Terminology\s*$(.*?)(?=^## )').Groups[1].Value
        $rows = @([regex]::Matches($section, '(?m)^\|(?!\s*-)(?!\s*Term\s*\|)\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|') | ForEach-Object { [pscustomobject]@{ Term = $_.Groups[1].Value; Names = $_.Groups[2].Value } })
        @($rows.Term) | Should -Be @('Id', 'node', 'edge', 'finding', 'graph', 'row', 'Source', 'tool', 'data file', 'sources', 'reservation', 'cloud range')

        # PSTypeName -> property names, from the hashtable literals that build each typed object.
        # Node properties beyond Id, Kind and Name come from the graph contract in the psm1.
        $files = @(Get-ChildItem -Path (Join-Path $ModuleRoot 'Public'), (Join-Path $ModuleRoot 'Private') -Filter '*.ps1' -File)
        $typed = @{}
        foreach ($file in $files) {
            $hashtables = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null).FindAll({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true)
            foreach ($hashtable in $hashtables) {
                $pair = $hashtable.KeyValuePairs | Where-Object { $_.Item1.Extent.Text -eq 'PSTypeName' } | Select-Object -First 1
                if (-not $pair) { continue }
                $typeName = $pair.Item2.Extent.Text.Trim('''', '"')
                if (-not $typed.ContainsKey($typeName)) { $typed[$typeName] = [System.Collections.Generic.HashSet[string]]::new() }
                foreach ($key in $hashtable.KeyValuePairs) { $null = $typed[$typeName].Add($key.Item1.Extent.Text.Trim('''', '"')) }
            }
        }
        $contract = InModuleScope NetworkGraph { $script:NetworkGraphNodeContract }
        foreach ($name in @($contract.Values | ForEach-Object { $_ }) + 'Source') { $null = $typed['NetworkGraph.Node'].Add($name) }
        $exported = @((Get-Module NetworkGraph).ExportedFunctions.Keys)

        foreach ($row in $rows) {
            $names = @([regex]::Matches($row.Names, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
            $names.Count | Should -BeGreaterThan 0 -Because "the '$($row.Term)' row must name something in the module"
            foreach ($name in $names) {
                $resolved = if ($name -match '^[A-Z][a-z]+-\w+$') { $exported -contains $name }
                elseif ($name -match '^(NetworkGraph\.\w+)\.(\w+)$') { $typed.ContainsKey($Matches[1]) -and $typed[$Matches[1]].Contains($Matches[2]) }
                elseif ($name -match '^NetworkGraph\.\w+$') { $typed.ContainsKey($name) }
                elseif ($name -match '[/\\]|\.(json|gz|md)$') { (Test-Path -LiteralPath (Join-Path $ModuleRoot $name)) -or (Test-Path -LiteralPath (Join-Path $RepoRoot $name)) }
                else { $false }
                $resolved | Should -BeTrue -Because "'$name' in the '$($row.Term)' row must be an exported command, NetworkGraph.<Type>[.<Property>] or a data file"
            }
        }
    }

    It "keeps the two doors: README's first line points to ONTOLOGY.md and ONTOLOGY.md links back first" {
        $readme = @(Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md'))
        $readme[0] | Should -Match '^>.*\]\(ONTOLOGY\.md\)'
        $ontology = @(Get-Content -LiteralPath (Join-Path $RepoRoot 'ONTOLOGY.md') | Where-Object { $_.Trim() })
        $ontology[0] | Should -BeLike '> *'
        $ontology[1] | Should -Match '\]\(README\.md\)'
    }
}
