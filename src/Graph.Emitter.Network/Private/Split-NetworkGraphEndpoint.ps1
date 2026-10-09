function Split-NetworkGraphEndpoint {
    # Not exported. 'address:port' as ss and netstat print it to { Ip, Port }: '10.0.0.1:443',
    # '[::1]:53', '[::ffff:10.0.0.1]:443' (unmapped to IPv4), '127.0.0.53%lo:53' (zone dropped),
    # '*:8080' (Ip 0.0.0.0), '0.0.0.0:*' (Port $null).
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Endpoint)

    $text = $Endpoint.Trim()
    $split = $text.LastIndexOf(':')
    if ($split -lt 0) { return [pscustomobject]@{ Ip = $null; Port = $null } }
    $address = $text.Substring(0, $split)
    $portText = $text.Substring($split + 1)
    $address = $address.Trim('[', ']')
    $zone = $address.IndexOf('%')
    if ($zone -ge 0) { $address = $address.Substring(0, $zone) }
    $ip = if ($address -eq '*') { '0.0.0.0' } else { (ConvertTo-NetworkGraphIpValue -Ip $address -Unmap).Ip }
    $port = $null
    if ($portText -ne '*') { $port = [int]$portText }
    [pscustomobject]@{ Ip = $ip; Port = $port }
}
