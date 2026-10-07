function ConvertTo-SubnetMask {
    <#
    .SYNOPSIS
        Converts an IPv4 prefix length to a dotted mask.

    .DESCRIPTION
        IPv4 only. A prefix length above 32 is a terminating error: IPv6 has no dotted mask, so
        use the prefix length itself.

    .PARAMETER PrefixLength
        0 to 32. Accepts the pipeline and objects with a PrefixLength property.

    .EXAMPLE
        ConvertTo-SubnetMask 26

        255.255.255.192

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [int]
        $PrefixLength
    )

    process {
        if ($PrefixLength -gt 32 -and $PrefixLength -le 128) {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new("Prefix length $PrefixLength is IPv6: IPv6 has no dotted subnet mask, use the prefix length (/$PrefixLength) itself."),
                    'IPv6HasNoMask', [System.Management.Automation.ErrorCategory]::InvalidArgument, $PrefixLength))
        }
        if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new("Prefix length $PrefixLength is out of range for IPv4 (0-32)."),
                    'PrefixLengthOutOfRange', [System.Management.Automation.ErrorCategory]::InvalidArgument, $PrefixLength))
        }
        $value = [System.Numerics.BigInteger]::Pow(2, 32) - [System.Numerics.BigInteger]::Pow(2, 32 - $PrefixLength)
        ConvertFrom-NetworkGraphIpValue -Value $value -Version 4
    }
}
