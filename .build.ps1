[CmdletBinding()]
Param(
    # UpdateData: kinds to harvest and promote.
    [ValidateSet('SpecialUse', 'CloudRanges', 'Oui', 'Ports')]
    [string[]]
    $Kind = @('SpecialUse', 'CloudRanges', 'Oui', 'Ports')
)

######################################################################################################
# InvokeBuild - ArgumentCompleters
######################################################################################################

Register-ArgumentCompleter -CommandName Invoke-Build.ps1 -ParameterName Task -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $boundParameters)

    (Invoke-Build -Task ?? -File ($boundParameters['File'])).get_Keys() -like "$wordToComplete*" | .{process{
        New-Object System.Management.Automation.CompletionResult $_, $_, 'ParameterValue', $_
    }}
}

Register-ArgumentCompleter -CommandName Invoke-Build.ps1 -ParameterName File -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $boundParameters)

    Get-ChildItem -Directory -Name "$wordToComplete*" | .{process{
        New-Object System.Management.Automation.CompletionResult $_, $_, 'ProviderContainer', $_
    }}

    if (!($boundParameters['Task'] -eq '**')) {
        Get-ChildItem -File -Name "$wordToComplete*.ps1" | .{process{
            New-Object System.Management.Automation.CompletionResult $_, $_, 'Command', $_
        }}
    }
}

######################################################################################################
# InvokeBuild - Install InvokeBuild
######################################################################################################

if (-not (Get-Module -ListAvailable -Name InvokeBuild)) {
    Install-Module -Name InvokeBuild -Scope CurrentUser -Verbose -Force
}

######################################################################################################
# Helpers
######################################################################################################

function Get-ModuleRoot {
    Join-Path $PSScriptRoot 'src' 'NetworkGraph'
}

function Get-ManifestVersion {
    [version](Import-PowerShellDataFile -Path (Join-Path (Get-ModuleRoot) 'NetworkGraph.psd1')).ModuleVersion
}

######################################################################################################
# Tasks
######################################################################################################

task RemoveModule {
    Remove-Module NetworkGraph -Force -ErrorAction SilentlyContinue
}

task ImportModule {
    Import-Module (Join-Path (Get-ModuleRoot) 'NetworkGraph.psd1') -Force -ErrorAction Stop
}

# Pester in a fresh process, so no module state from this shell leaks into the run.
task Test {
    $tests = Join-Path $PSScriptRoot 'tests'
    if (-not (Get-ChildItem -Path $tests -Filter '*.Tests.ps1' -Recurse -ErrorAction SilentlyContinue)) {
        throw "No *.Tests.ps1 files found under $tests"
    }
    exec { pwsh -NoProfile -Command "Set-Location '$PSScriptRoot'; Invoke-Pester -Path .\tests -CI" }
}

task Analyze {
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
    }
    $results = @(Invoke-ScriptAnalyzer -Path (Get-ModuleRoot) -Recurse -Severity Warning, Error)
    $results | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize -Wrap | Out-String -Width 200 | Write-Host
    if (@($results | Where-Object Severity -eq 'Error').Count) {
        throw "PSScriptAnalyzer found $(@($results | Where-Object Severity -eq 'Error').Count) error(s)."
    }
}

# One-file module in dist/NetworkGraph/<version>: the psm1 region that dot-sources Private/ and
# Public/ is replaced with their contents; manifest, data, skills, LICENSE and NOTICE are copied as is.
task Assemble {
    $root = Get-ModuleRoot
    $version = Get-ManifestVersion
    $out = Join-Path $PSScriptRoot 'dist' 'NetworkGraph' $version
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $out -Force

    $psm1 = Get-Content -Raw (Join-Path $root 'NetworkGraph.psm1')
    $pattern = '(?s)#region functions.*?#endregion functions'
    if ($psm1 -notmatch $pattern) { throw 'NetworkGraph.psm1 has no #region functions block to replace.' }
    $body = [System.Text.StringBuilder]::new()
    foreach ($folder in 'Private', 'Public') {
        foreach ($file in Get-ChildItem -Path (Join-Path $root $folder) -Filter '*.ps1' -File | Sort-Object Name) {
            $null = $body.AppendLine("# $folder\$($file.Name)").AppendLine((Get-Content -Raw $file.FullName).TrimEnd()).AppendLine()
        }
    }
    $assembled = [regex]::Replace($psm1, $pattern, { param($m) $body.ToString().TrimEnd() })
    [System.IO.File]::WriteAllText((Join-Path $out 'NetworkGraph.psm1'), $assembled, [System.Text.UTF8Encoding]::new($false))
    Copy-Item (Join-Path $root 'NetworkGraph.psd1') $out
    Copy-Item (Join-Path $root 'data') $out -Recurse
    Copy-Item (Join-Path $root 'skills') $out -Recurse
    Copy-Item (Join-Path $PSScriptRoot 'LICENSE'), (Join-Path $PSScriptRoot 'NOTICE') $out

    exec { pwsh -NoProfile -Command "`$m = Import-Module '$out\NetworkGraph.psd1' -PassThru -ErrorAction Stop; '{0} {1}: {2} commands' -f `$m.Name, `$m.Version, `$m.ExportedFunctions.Count" }
    Write-Host "Assembled $out"
}

# Harvest into the user cache with Update-NetworkGraphData, then promote the harvested files to
# src/NetworkGraph/data. The only path by which harvested data reaches src/. Network.
task UpdateData RemoveModule, ImportModule, {
    $rows = @(Update-NetworkGraphData -Kind $Kind -PassThru -ErrorAction Stop)
    $target = Join-Path (Get-ModuleRoot) 'data'
    foreach ($row in $rows) {
        Copy-Item -LiteralPath $row.Path -Destination (Join-Path $target $row.File) -Force
        Write-Host ('{0,-12} {1,-22} {2,10:n0} bytes {3,7:n0} entries pulled {4}' -f $row.Kind, $row.File, $row.Bytes, $row.Entries, $row.Pulled)
    }
    exec { git -C $PSScriptRoot --no-pager diff --stat -- src/NetworkGraph/data }
}

# Every bundled data file: has sources with a url and a pulled date, and is no older than its
# maxAgeDays. Fails listing each stale or unsourced file and the command that refreshes it.
task CheckData {
    $problems = [System.Collections.Generic.List[string]]::new()
    $files = Get-ChildItem -Path (Join-Path (Get-ModuleRoot) 'data') -File | Where-Object Name -match '\.json(\.gz)?$'
    $rows = foreach ($file in $files) {
        $text = if ($file.Extension -eq '.gz') {
            $stream = [System.IO.Compression.GZipStream]::new([System.IO.File]::OpenRead($file.FullName), [System.IO.Compression.CompressionMode]::Decompress)
            try { [System.IO.StreamReader]::new($stream).ReadToEnd() } finally { $stream.Dispose() }
        }
        else { [System.IO.File]::ReadAllText($file.FullName) }
        $doc = $text | ConvertFrom-Json -AsHashtable -Depth 64
        $sources = @($doc['sources'])
        $pulled = $doc['pulled'] ?? (@($sources | ForEach-Object { $_['pulled'] } | Sort-Object) | Select-Object -Last 1)
        $age = $pulled ? [int]([datetime]::UtcNow.Date - [datetime]::ParseExact($pulled, 'yyyy-MM-dd', $null)).TotalDays : $null
        $status = 'Fresh'
        if (-not $sources.Count -or @($sources | Where-Object { -not $_['url'] -or -not $_['pulled'] }).Count) {
            $status = 'Unsourced'
            $problems.Add("$($file.Name): every source needs a url and a pulled date.")
        }
        elseif ($null -ne $doc['maxAgeDays'] -and $age -gt [int]$doc['maxAgeDays']) {
            $status = 'Stale'
            $fix = ($doc['kind'] -in 'SpecialUse', 'CloudRanges', 'Oui', 'Ports') ? "Invoke-Build UpdateData -Kind $($doc['kind'])" : "re-read the sources of $($file.Name) and edit it by hand"
            $problems.Add("$($file.Name): pulled $pulled, $age days old, max $($doc['maxAgeDays']). Fix: $fix")
        }
        [pscustomobject]@{ File = $file.Name; Kind = $doc['kind']; Pulled = $pulled; AgeDays = $age; MaxAgeDays = $doc['maxAgeDays']; Sources = $sources.Count; Bytes = $file.Length; Status = $status }
    }
    $rows | Format-Table -AutoSize | Out-String | Write-Host
    if ($problems.Count) { throw "Data not fresh:`n$($problems -join "`n")" }
}

task . Test
