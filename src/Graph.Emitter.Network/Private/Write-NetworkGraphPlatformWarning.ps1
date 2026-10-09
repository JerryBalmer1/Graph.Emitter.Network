function Write-NetworkGraphPlatformWarning {
    # Not exported. Called once by Graph.Emitter.Network.psm1 at import: on macOS the module runs but is
    # untested (the observe commands take their Linux paths, and some Linux floors do not exist
    # there), so say so once rather than fail later with a stack trace.
    if ($script:NetworkGraphPlatform -eq 'macOS') {
        Write-Warning 'Graph.Emitter.Network is untested on macOS: the calculate and graph commands work, but the observe commands take their Linux paths and some have no .NET floor there (Get-NetworkNeighbor). Windows and Linux are supported.'
    }
}
