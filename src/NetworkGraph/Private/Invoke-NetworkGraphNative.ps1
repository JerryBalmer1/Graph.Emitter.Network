function Invoke-NetworkGraphNative {
    # Not exported. Runs one installed command and returns { CommandLine, ExitCode, Output, Error,
    # TimedOut }: the exact command line (for Source), stdout and stderr as text. Never a shell, so
    # arguments are passed as given. Kills the process after -TimeoutSec. Tests set
    # $script:NetworkGraphNativeInvoker to a scriptblock taking (FilePath, ArgumentList) and
    # returning the same shape; no test runs a real tool unless tagged Live.
    param(
        [Parameter(Mandatory)]
        [string]
        $FilePath,

        [string[]]
        $ArgumentList = @(),

        [int]
        $TimeoutSec = 120
    )

    $quoted = foreach ($argument in $ArgumentList) { ($argument -match '[\s"]') ? ('"{0}"' -f ($argument -replace '"', '\"')) : $argument }
    $commandLine = (@($FilePath) + @($quoted)) -join ' '
    if ($script:NetworkGraphNativeInvoker) {
        $result = & $script:NetworkGraphNativeInvoker $FilePath $ArgumentList
        $result | Add-Member -NotePropertyName CommandLine -NotePropertyValue $commandLine -Force
        return $result
    }

    $command = Get-Command -Name $FilePath -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $info = [System.Diagnostics.ProcessStartInfo]::new($command.Source)
    foreach ($argument in $ArgumentList) { $info.ArgumentList.Add($argument) }
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSec * 1000)
        if ($timedOut) { try { $process.Kill($true) } catch { Write-Verbose $_.Exception.Message } }
        $process.WaitForExit()
        [pscustomobject]@{
            CommandLine = $commandLine
            ExitCode    = $timedOut ? $null : $process.ExitCode
            Output      = $stdout.GetAwaiter().GetResult()
            Error       = $stderr.GetAwaiter().GetResult()
            TimedOut    = $timedOut
        }
    }
    finally {
        $process.Dispose()
    }
}
