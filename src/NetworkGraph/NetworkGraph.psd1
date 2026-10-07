@{
    RootModule        = 'NetworkGraph.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '5d0f6c3e-8a4b-4f61-9e2a-1c7b3d9a6e40'
    Author            = 'Jerry Balmer'
    CompanyName       = 'Jerry Balmer'
    Copyright         = '(c) Jerry Balmer. All rights reserved.'
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
            ProjectUri                 = 'https://github.com/JerryBalmer1/NetworkGraph'
            LicenseUri                 = 'https://github.com/JerryBalmer1/NetworkGraph/blob/main/LICENSE'
            ReleaseNotes               = '0.1.0: Initial release. Calculate: Get-Subnet (cloud reservations for Azure, AWS, GCP), New-SubnetPlan, Test-SubnetOverlap, Get-SubnetParent, Get-SubnetChildren, ConvertTo-SubnetMask, ConvertFrom-SubnetMask, Test-IPAddress, Get-MacAddressVendor. Observe: Test-NetworkPath, Trace-NetworkPath, Test-NetworkPort, Get-NetworkConnection, Get-NetworkNeighbor, Get-NetworkRoute, Get-NetworkInterface, Resolve-NetworkName, Get-ExternalIpAddress, Get-NetworkHost, Invoke-NetworkScan. Graph and data: ConvertTo-NetworkGraph, Get-NetworkGraphData, Update-NetworkGraphData.'
            RequireLicenseAcceptance   = $false
            ExternalModuleDependencies = @()
        }
    }
}
