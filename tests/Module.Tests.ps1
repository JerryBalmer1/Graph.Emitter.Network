BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:PublicFiles = @(Get-ChildItem -Path (Join-Path $ModuleRoot 'Public') -Filter '*.ps1')
    $script:Manifest = Import-PowerShellDataFile -Path (Join-Path $ModuleRoot 'NetworkGraph.psd1')
}

Describe 'Module' {
    It 'is version 0.1.0 and needs PowerShell 7.4' {
        $Manifest.ModuleVersion | Should -Be '0.1.0'
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
