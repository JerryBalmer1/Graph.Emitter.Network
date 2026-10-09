function Resolve-NetworkGraphTool {
    # Not exported. Picks the tool an observe command uses: the first installed -Candidate (an
    # executable or a cmdlet) for Auto and Native, or 'DotNet'. Auto falls back to DotNet when no
    # candidate is installed; Native without one is a terminating error naming -Tool DotNet. A
    # command with no .NET floor on this platform passes -NoDotNet: then DotNet, or Auto with
    # nothing installed, is a terminating error naming the tools to install.
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Auto', 'Native', 'DotNet')]
        [string]
        $Tool,

        [string[]]
        $Candidate = @(),

        [string]
        $CommandName,

        [string]
        $NoDotNet
    )

    if ($Tool -ne 'DotNet') {
        foreach ($name in $Candidate) {
            if (Get-Command -Name $name -ErrorAction SilentlyContinue) { return $name }
        }
        if ($Tool -eq 'Native') {
            $platform = $IsWindows ? 'Windows' : ($IsLinux ? 'Linux' : 'this platform')
            $names = $Candidate ? ($Candidate -join ', ') : 'none'
            $fix = $NoDotNet ? "Install one of them." : "Install one, or run $CommandName -Tool DotNet."
            throw [System.Management.Automation.CommandNotFoundException]::new("$CommandName -Tool Native: no native tool found on $platform (looked for: $names). $fix")
        }
    }
    if ($NoDotNet) {
        throw [System.PlatformNotSupportedException]::new("$CommandName has no .NET floor here: $NoDotNet Install $($Candidate -join ' or ') and run $CommandName -Tool Native.")
    }
    'DotNet'
}
