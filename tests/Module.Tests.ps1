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
