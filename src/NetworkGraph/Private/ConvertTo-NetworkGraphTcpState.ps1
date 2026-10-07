function ConvertTo-NetworkGraphTcpState {
    # Not exported. A connection state from any tool in the names Windows and
    # System.Net.NetworkInformation.TcpState use (Listen, Established, TimeWait, ...). ss spells
    # them LISTEN, ESTAB, TIME-WAIT; an unconnected UDP socket (UNCONN) has no state ($null).
    param([AllowEmptyString()][AllowNull()][string]$State)

    if (-not $State) { return $null }
    $map = @{
        'LISTEN' = 'Listen'; 'ESTAB' = 'Established'; 'ESTABLISHED' = 'Established'; 'TIME-WAIT' = 'TimeWait'; 'TIME_WAIT' = 'TimeWait'
        'CLOSE-WAIT' = 'CloseWait'; 'CLOSE_WAIT' = 'CloseWait'; 'SYN-SENT' = 'SynSent'; 'SYN_SENT' = 'SynSent'; 'SYN-RECV' = 'SynReceived'; 'SYN_RECV' = 'SynReceived'
        'FIN-WAIT-1' = 'FinWait1'; 'FIN_WAIT1' = 'FinWait1'; 'FIN-WAIT-2' = 'FinWait2'; 'FIN_WAIT2' = 'FinWait2'; 'CLOSING' = 'Closing'
        'LAST-ACK' = 'LastAck'; 'LAST_ACK' = 'LastAck'; 'CLOSED' = 'Closed'; 'UNCONN' = $null
    }
    $key = $State.ToUpperInvariant()
    if ($map.ContainsKey($key)) { return $map[$key] }
    $State
}
