function Invoke-NetworkGraphNative {
    # Not exported. Runs one installed command and returns { CommandLine, ExitCode, Output, Error,
    # TimedOut }: the exact command line (for Source), stdout and stderr as text. Never a shell, so
    # arguments are passed as given. Kills the process after -TimeoutSec. On Linux and macOS the
    # child runs with LC_ALL=C and LANG=C, so its messages are the English the parsers read.
    #
    # The one place native results are checked: an exit code not in -OkExitCodes (every caller
    # declares its own, for example ping 0 and 1, since 1 means no reply), or a timeout, throws
    # with the exit code, stderr and the command line; partial output is never parsed as complete.
    #
    # Tests set $script:NetworkGraphNativeInvoker to a scriptblock taking (FilePath, ArgumentList)
    # and returning the same shape; the checks apply to its result too. No test runs a real tool
    # unless tagged Live.
    param(
        [Parameter(Mandatory)]
        [string]
        $FilePath,

        [string[]]
        $ArgumentList = @(),

        [int]
        $TimeoutSec = 120,

        [Parameter(Mandatory)]
        [int[]]
        $OkExitCodes
    )

    $quoted = foreach ($argument in $ArgumentList) { ($argument -match '[\s"]') ? ('"{0}"' -f ($argument -replace '"', '\"')) : $argument }
    $commandLine = (@($FilePath) + @($quoted)) -join ' '
    $check = {
        param($Result, $Ok)
        if ($Result.TimedOut) {
            throw [System.TimeoutException]::new("$FilePath timed out after $TimeoutSec s; its partial output was discarded. Command: $commandLine")
        }
        if ($Result.ExitCode -notin $Ok) {
            $stderr = ([string]$Result.Error).Trim()
            $detail = $stderr ? $stderr : '(no stderr)'
            throw [System.InvalidOperationException]::new("$FilePath failed with exit code $($Result.ExitCode) (expected $($Ok -join ' or ')): $detail Command: $commandLine")
        }
        $Result
    }

    if ($script:NetworkGraphNativeInvoker) {
        $result = & $script:NetworkGraphNativeInvoker $FilePath $ArgumentList
        $result | Add-Member -NotePropertyName CommandLine -NotePropertyValue $commandLine -Force
        return & $check $result $OkExitCodes
    }

    $command = Get-Command -Name $FilePath -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $info = [System.Diagnostics.ProcessStartInfo]::new($command.Source)
    foreach ($argument in $ArgumentList) { $info.ArgumentList.Add($argument) }
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    if (-not $IsWindows) {
        $info.Environment['LC_ALL'] = 'C'
        $info.Environment['LANG'] = 'C'
    }
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSec * 1000)
        if ($timedOut) { try { $process.Kill($true) } catch { Write-Verbose $_.Exception.Message } }
        $process.WaitForExit()
        & $check ([pscustomobject]@{
                CommandLine = $commandLine
                ExitCode    = $timedOut ? $null : $process.ExitCode
                Output      = $stdout.GetAwaiter().GetResult()
                Error       = $stderr.GetAwaiter().GetResult()
                TimedOut    = $timedOut
            }) $OkExitCodes
    }
    finally {
        $process.Dispose()
    }
}
