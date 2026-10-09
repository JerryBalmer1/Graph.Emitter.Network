function Get-MacAddressVendor {
    <#
    .SYNOPSIS
        Looks up the vendor of a MAC address and reads its locally-administered and multicast bits.

    .DESCRIPTION
        Offline, from data/oui.json (IEEE MA-L assignments, 24-bit OUIs). Accepts any common
        notation: 00-1A-2B-3C-4D-5E, 00:1a:2b:3c:4d:5e, 001a.2b3c.4d5e, 001A2B3C4D5E.

        Windows, iOS and Android randomise the MAC address they show each network, and a random
        address sets the locally-administered bit. Such an address has no vendor: Vendor is $null
        and IsRandomized is $true. The vendor is only trustworthy when IsLocallyAdministered is
        $false.

    .PARAMETER MacAddress
        One or more MAC addresses. Accepts the pipeline and objects with a MacAddress property.

    .EXAMPLE
        Get-MacAddressVendor 00-15-5D-01-02-03

        Microsoft Corporation (Hyper-V).

    .OUTPUTS
        NetworkGraph.MacVendor: MacAddress, Oui, Vendor, IsLocallyAdministered, IsMulticast,
        IsRandomized, Source.
    #>
    [CmdletBinding()]
    [OutputType('NetworkGraph.MacVendor')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowEmptyString()]
        [string[]]
        $MacAddress
    )

    begin {
        $document = Get-NetworkGraphDataDocument -Kind Oui
        $source = @($document['sources'])[0]['url']
    }
    process {
        foreach ($text in $MacAddress) {
            $hex = ([string]$text) -replace '[-:.\s]', ''
            if ($hex -notmatch '^[0-9A-Fa-f]{12}$') {
                Write-Error -Message "'$text' is not a MAC address (six bytes, for example 00-1A-2B-3C-4D-5E)." -ErrorId 'InvalidMacAddress' -Category InvalidArgument -TargetObject $text
                continue
            }
            $hex = $hex.ToUpperInvariant()
            $first = [Convert]::ToByte($hex.Substring(0, 2), 16)
            $local = [bool]($first -band 2)
            $oui = $hex.Substring(0, 6)
            $vendor = $local ? $null : $document['entries'][$oui]
            [pscustomobject]@{
                PSTypeName            = 'NetworkGraph.MacVendor'
                MacAddress            = ($hex -split '(..)' -ne '') -join '-'
                Oui                   = '{0}-{1}-{2}' -f $oui.Substring(0, 2), $oui.Substring(2, 2), $oui.Substring(4, 2)
                Vendor                = $vendor
                IsLocallyAdministered = $local
                IsMulticast           = [bool]($first -band 1)
                IsRandomized          = $local
                Source                = $source
            }
        }
    }
}
