@{
    RootModule        = 'Graph.Emitter.Network.psm1'
    ModuleVersion     = '0.3.0'
    GUID              = '5d0f6c3e-8a4b-4f61-9e2a-1c7b3d9a6e40'
    Author            = 'Jerry Balmer'
    CompanyName       = 'Jerry Balmer'
    Copyright         = '(c) 2026 Jerry Balmer. Licensed under the Apache License, Version 2.0.'
    Description       = 'Subnet math with cloud reservations, auditable wrappers over the network tools already installed, and a graph of what a host can see.'
    PowerShellVersion = '7.4'
    # Group 1 calculate (Subnet, IPAddress, MacAddress nouns), group 2 observe (Network* and
    # ExternalIpAddress nouns), group 3 graph and data (NetworkGraph* nouns). Sorted within a group.
    FunctionsToExport = @(
        'ConvertFrom-SubnetMask'
        'ConvertTo-SubnetMask'
        'Get-MacAddressVendor'
        'Get-Subnet'
        'Get-SubnetChildren'
        'Get-SubnetParent'
        'New-SubnetPlan'
        'Test-IPAddress'
        'Test-SubnetOverlap'

        'Get-ExternalIpAddress'
        'Get-NetworkConnection'
        'Get-NetworkHost'
        'Get-NetworkInterface'
        'Get-NetworkNeighbor'
        'Get-NetworkRoute'
        'Invoke-NetworkScan'
        'Resolve-NetworkName'
        'Test-NetworkPath'
        'Test-NetworkPort'
        'Trace-NetworkPath'

        'ConvertTo-NetworkGraph'
        'Get-NetworkGraphData'
        'Update-NetworkGraphData'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags                       = @('Network', 'Subnet', 'CIDR', 'IPAM', 'Azure', 'AWS', 'GCP', 'Graph', 'PowerShell', 'PowerShell74')
            ProjectUri                 = 'https://github.com/JerryBalmer1/Graph.Emitter.Network'
            LicenseUri                 = 'https://github.com/JerryBalmer1/Graph.Emitter.Network/blob/main/LICENSE'
            ReleaseNotes               = '0.3.0: Renamed from NetworkGraph; module and manifest follow the repo name (Graph.Emitter.Network); no functional change. 0.1.1: Graph contract: Hop nodes gain AvgMs and Responded (LossPercent is empty for a silent hop a later hop answered past; mtr and pathping averages move to AvgMs), Hop Ids carry the tool, Connection Ids carry the PID; rows from Invoke-Command or a job are graphed. Fixes: Get-ExternalIpAddress -Rdap reports the CIDR block that holds the address; Get-NetworkHost reports a third-party firewall (Windows Security Center) as ThirdParty and reads ufw.conf without root. Native tools: every exit code and timeout is checked in one place, text output a parser does not recognise is an error naming -Tool DotNet, Linux tools run with LC_ALL=C, and on Windows Test-NetworkPath and Trace-NetworkPath default to the .NET path. Every Source is a pasteable command, .NET expression or data citation. Test-NetworkPort LatencyMs is timed per connect. macOS: one import warning, and Get-NetworkNeighbor says it has no .NET floor there. Fixtures: ISP infrastructure scrubbed. 0.1.0: Initial release. Calculate: Get-Subnet (cloud reservations for Azure, AWS, GCP), New-SubnetPlan, Test-SubnetOverlap, Get-SubnetParent, Get-SubnetChildren, ConvertTo-SubnetMask, ConvertFrom-SubnetMask, Test-IPAddress, Get-MacAddressVendor. Observe: Test-NetworkPath, Trace-NetworkPath, Test-NetworkPort, Get-NetworkConnection, Get-NetworkNeighbor, Get-NetworkRoute, Get-NetworkInterface, Resolve-NetworkName, Get-ExternalIpAddress, Get-NetworkHost, Invoke-NetworkScan. Graph and data: ConvertTo-NetworkGraph, Get-NetworkGraphData, Update-NetworkGraphData.'
            RequireLicenseAcceptance   = $false
            ExternalModuleDependencies = @()
        }
    }
}
