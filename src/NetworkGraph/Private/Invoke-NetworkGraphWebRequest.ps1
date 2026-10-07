function Invoke-NetworkGraphWebRequest {
    # Not exported. The only HTTP call in the module: GET over HTTPS, redirects followed. Returns
    # { Uri (after redirects), StatusCode, Content (UTF-8 text) }. Tests set
    # $script:NetworkGraphWebInvoker to a scriptblock taking the Uri and returning the same shape.
    param(
        [Parameter(Mandatory)]
        [string]
        $Uri,

        [int]
        $TimeoutSec = 60,

        [hashtable]
        $Headers = @{}
    )

    if ($script:NetworkGraphWebInvoker) { return & $script:NetworkGraphWebInvoker $Uri }
    if (-not $Uri.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw [System.ArgumentException]::new("NetworkGraph only requests HTTPS URLs; '$Uri' is not one.")
    }

    $version = $MyInvocation.MyCommand.Module.Version
    $response = Invoke-WebRequest -Uri $Uri -TimeoutSec $TimeoutSec -Headers $Headers -MaximumRedirection 5 -UserAgent "NetworkGraph/$version (+https://github.com/JerryBalmer1/NetworkGraph)" -ErrorAction Stop
    $final = $response.BaseResponse.RequestMessage.RequestUri
    [pscustomobject]@{
        Uri        = $final ? $final.AbsoluteUri : $Uri
        StatusCode = [int]$response.StatusCode
        Content    = [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
    }
}
