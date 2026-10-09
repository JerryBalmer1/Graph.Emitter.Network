function ConvertFrom-SubnetMask {
    <#
    .SYNOPSIS
        Converts a dotted IPv4 mask to its prefix length.

    .DESCRIPTION
        IPv4 only. An IPv6 value is a terminating error (IPv6 has no dotted mask), and so is a mask
        whose one bits are not contiguous, such as 255.0.255.0.

    .PARAMETER Mask
        Dotted IPv4 mask. Accepts the pipeline and objects with a Mask property.

    .EXAMPLE
        ConvertFrom-SubnetMask 255.255.240.0

        20

    .OUTPUTS
        System.Int32
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $Mask
    )

    process {
        if ($Mask.Contains(':')) {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new("'$Mask' is IPv6: IPv6 has no dotted subnet mask, write the prefix length (for example /64) instead."),
                    'IPv6HasNoMask', [System.Management.Automation.ErrorCategory]::InvalidArgument, $Mask))
        }
        try {
            $value = [uint32](ConvertTo-NetworkGraphIpValue -Ip $Mask).Value
        }
        catch {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new("'$Mask' is not a dotted IPv4 mask, for example 255.255.255.0."),
                    'InvalidMask', [System.Management.Automation.ErrorCategory]::InvalidArgument, $Mask))
        }
        $length = 0
        while ($length -lt 32 -and ($value -band ([uint32]1 -shl (31 - $length)))) { $length++ }
        $expected = [uint32]([System.Numerics.BigInteger]::Pow(2, 32) - [System.Numerics.BigInteger]::Pow(2, 32 - $length))
        if ($value -ne $expected) {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new("'$Mask' is not a valid mask: its one bits are not contiguous from the left."),
                    'NonContiguousMask', [System.Management.Automation.ErrorCategory]::InvalidArgument, $Mask))
        }
        $length
    }
}
