function ConvertFrom-NetworkGraphHopText {
    # Not exported. The responder of one hop line: '1.2.3.4', 'name [1.2.3.4]' (Windows) or
    # 'name (1.2.3.4)' (Linux) to { Ip, Host }; anything else ('Request timed out.') to nulls.
    param([AllowEmptyString()][string]$Text)

    $text = $Text.Trim()
    $ip = $null
    $hostName = $null
    if ($text -match '^(\S+)\s+[\[(]([0-9A-Fa-f:.]+)[\])]$') { $hostName = $Matches[1]; $ip = $Matches[2] }
    elseif ($text -match '^[0-9A-Fa-f:.]+$' -and ($text.Contains(':') -or $text -match '^\d+(\.\d+){3}$')) { $ip = $text }
    [pscustomobject]@{ Ip = $ip; Host = $hostName }
}
