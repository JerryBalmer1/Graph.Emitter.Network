BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:DataRoot = Join-Path $ModuleRoot 'data'
}

Describe 'Update-NetworkGraphData' {
    BeforeAll {
        $script:WebFixture = @{
            'https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry-1.csv' = "Address Block,Name,RFC,Allocation Date,Termination Date,Source,Destination,Forwardable,Globally Reachable,Reserved-by-Protocol`n10.0.0.0/8,Private-Use,[RFC1918],1996-02,N/A,True,True,True,False,False`n"
            'https://www.iana.org/assignments/iana-ipv6-special-registry/iana-ipv6-special-registry-1.csv' = "Address Block,Name,RFC,Allocation Date,Termination Date,Source,Destination,Forwardable,Globally Reachable,Reserved-by-Protocol`n2001::/32,TEREDO,`"[RFC4380]`n        [RFC8190]`",2006-01,N/A,True,True,True,N/A [2],False`n"
            'https://standards-oui.ieee.org/oui/oui.csv'                                                    = "Registry,Assignment,Organization Name,Organization Address`nMA-L,00155D,Microsoft Corporation,One Microsoft Way`n"
        }
        $table = $WebFixture
        InModuleScope Graph.Emitter.Network -Parameters @{ Table = $table } {
            param($Table)
            $script:NetworkGraphWebInvoker = { param($Uri) [pscustomobject]@{ Uri = $Uri; StatusCode = 200; Content = $Table[$Uri] } }.GetNewClosure()
        }
    }
    AfterAll { Clear-NativeFixture }

    It 'harvests into the folder given and never into src' {
        $before = (Get-ChildItem $DataRoot -File | ForEach-Object { "$($_.Name)|$($_.LastWriteTimeUtc.Ticks)" }) -join ';'
        $target = Join-Path $TestDrive 'harvest'
        $rows = @(Update-NetworkGraphData -Kind SpecialUse, Oui -Path $target -PassThru)
        $rows.Kind | Should -Be @('SpecialUse', 'Oui')
        $rows[0].Location | Should -Be 'Path'
        $rows[0].Entries | Should -Be 4
        (Get-ChildItem $DataRoot -File | ForEach-Object { "$($_.Name)|$($_.LastWriteTimeUtc.Ticks)" }) -join ';' | Should -Be $before
        $special = Get-Content -Raw (Join-Path $target 'special-use.json') | ConvertFrom-Json
        ($special.entries | Where-Object cidr -eq '2001::/32').scope | Should -Be 'SpecialPurpose'
        ($special.entries | Where-Object cidr -eq '10.0.0.0/8').rfcUrl | Should -Be 'https://www.rfc-editor.org/rfc/rfc1918'
        (Get-Content -Raw (Join-Path $target 'oui.json') | ConvertFrom-Json).entries.'00155D' | Should -Be 'Microsoft Corporation'
    }

    It 'writes the user cache by default, which then wins over the bundled copy' {
        Update-NetworkGraphData -Kind Oui
        (Get-NetworkGraphData | Where-Object Kind -eq Oui).Location | Should -Be 'User'
        (Get-MacAddressVendor 00-15-5D-00-00-01).Vendor | Should -Be 'Microsoft Corporation'
        Remove-Item (Join-Path $TestDrive 'user-data' 'oui.json')
        (Get-NetworkGraphData | Where-Object Kind -eq Oui).Location | Should -Be 'Bundled'
    }

    It 'harvests the real sources' -Tag Live -Skip:(-not $env:NETWORKGRAPH_LIVE) {
        Clear-NativeFixture
        $rows = @(Update-NetworkGraphData -Path (Join-Path $TestDrive 'live') -PassThru)
        $rows.Count | Should -Be 4
        ($rows | Where-Object Kind -eq CloudRanges).Entries | Should -BeGreaterThan 10000
    }
}
