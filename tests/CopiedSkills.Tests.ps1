# The skills copied read-only from Graph (git-guard, run-report, graph-node): each one's version: and the full text of
# every file against Graph's committed (HEAD) copy, the git-guard hook's pinned exit codes, and its settings.json entry.
# Self-contained: compares with `git -C C:\__Code\Graph show HEAD:`, never Graph's working tree.

BeforeDiscovery {
    $script:Skills = @(
        @{ Skill = 'git-guard'; Source = 'C:\__Code\Graph' }
        @{ Skill = 'run-report'; Source = 'C:\__Code\Graph' }
        @{ Skill = 'graph-node'; Source = 'C:\__Code\Graph' }
    )
    # The six commands Graph pins the hook to.
    $script:Commands = @(
        @{ Command = 'git status'; Code = 0 }
        @{ Command = 'git add -A'; Code = 0 }
        @{ Command = 'git commit -m x'; Code = 2 }
        @{ Command = 'git push'; Code = 2 }
        @{ Command = 'git tag v1'; Code = 2 }
        @{ Command = 'gh pr merge 12 --squash'; Code = 2 }
    )
}

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:Hook = Join-Path $RepoRoot '.claude' 'skills' 'git-guard' 'hook.ps1'
    $script:Message = 'git-guard: agents edit and stage only; commits are run by Jerry from a separate shell'

    # The version: in a SKILL.md's front matter.
    function Get-FrontVersion([string] $Text) {
        $front = [regex]::Match($Text, '\A---\r?\n(.*?)\r?\n---', 'Singleline').Groups[1].Value
        [regex]::Match($front, '(?m)^version:\s*(\S+)\s*$').Groups[1].Value
    }
    # Runs git in another checkout with UTF-8 output; returns its stdout lines, or $null when git fails.
    function Invoke-CheckoutGit([string] $Repo, [string[]] $Arguments) {
        if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) { return $null }
        $encoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        try { $out = & git -C $Repo -c core.quotepath=off @Arguments 2>$null } finally { [Console]::OutputEncoding = $encoding }
        if ($LASTEXITCODE -ne 0) { return $null }
        @($out)
    }
    # The committed (HEAD) text of a file in another checkout, lines joined with LF; $null when missing.
    function Get-CommittedText([string] $Repo, [string] $RelativePath) {
        $lines = Invoke-CheckoutGit $Repo @('show', "HEAD:$RelativePath")
        if ($null -eq $lines) { return $null }
        $lines -join "`n"
    }
    # Pipes a Bash tool call's hook JSON into hook.ps1 in a fresh process; returns its exit code and stderr.
    function Invoke-Hook([string] $Command) {
        $raw = ConvertTo-Json -Compress -InputObject @{ tool_name = 'Bash'; tool_input = @{ command = $Command } }
        $err = Join-Path $TestDrive 'hook.err'
        $raw | & pwsh -NoProfile -File $Hook 2> $err | Out-Null
        [pscustomobject]@{ Code = $LASTEXITCODE; Error = (Get-Content -LiteralPath $err -Raw) }
    }
}

Describe 'Copied skills (read-only here)' {
    It '<Skill> has the version: of the committed copy in <Source>' -ForEach $Skills {
        $committed = Get-CommittedText $Source ".claude/skills/$Skill/SKILL.md"
        if ($null -eq $committed) {
            Set-ItResult -Skipped -Because "$Source is not a git checkout with .claude/skills/$Skill committed"
            return
        }
        $mine = Get-FrontVersion (Get-Content -LiteralPath (Join-Path $RepoRoot '.claude' 'skills' $Skill 'SKILL.md') -Raw)
        $mine | Should -Match '^\d+\.\d+\.\d+$'
        $mine | Should -Be (Get-FrontVersion $committed) -Because "recopy .claude/skills/$Skill from $Source\.claude\skills\$Skill"
    }

    It '<Skill> holds every file of the committed copy in <Source>, text identical, line endings aside' -ForEach $Skills {
        $files = @(Invoke-CheckoutGit $Source @('ls-tree', '-r', '--name-only', 'HEAD', '--', ".claude/skills/$Skill"))
        if (-not $files) {
            Set-ItResult -Skipped -Because "$Source is not a git checkout with .claude/skills/$Skill committed"
            return
        }
        $dir = Join-Path $RepoRoot '.claude' 'skills' $Skill
        $mine = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force | ForEach-Object { [IO.Path]::GetRelativePath($RepoRoot, $_.FullName) -replace '\\', '/' })
        ($mine | Sort-Object) | Should -Be ($files | Sort-Object)
        foreach ($f in $files) {
            ((Get-Content -LiteralPath (Join-Path $RepoRoot $f) -Encoding utf8) -join "`n") | Should -BeExactly (Get-CommittedText $Source $f) -Because $f
        }
    }
}

Describe 'git-guard hook (copied from Graph)' {
    It 'exits <Code> for <Command>' -ForEach $Commands {
        $r = Invoke-Hook -Command $Command
        $r.Code | Should -Be $Code -Because $r.Error
        if ($Code -eq 2) { $r.Error.Trim() | Should -Be $Message }
    }

    It '.claude/settings.json has the fragment''s PreToolUse entry, beside any other settings' {
        $fragment = Get-Content -LiteralPath (Join-Path $RepoRoot '.claude' 'skills' 'git-guard' 'settings.fragment.json') -Raw | ConvertFrom-Json
        $settings = Get-Content -LiteralPath (Join-Path $RepoRoot '.claude' 'settings.json') -Raw | ConvertFrom-Json
        $want = @($fragment.hooks.PreToolUse)
        $want.Count | Should -Be 1
        $have = @($settings.hooks.PreToolUse | ForEach-Object { ConvertTo-Json -Depth 6 -Compress $_ })
        $have | Should -Contain (ConvertTo-Json -Depth 6 -Compress $want[0])
    }
}
