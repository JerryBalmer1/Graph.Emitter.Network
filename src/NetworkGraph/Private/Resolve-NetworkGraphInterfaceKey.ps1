function Resolve-NetworkGraphInterfaceKey {
    # Not exported. The InterfaceKey for an interface a row names by index, by name, or both, from a
    # Get-NetworkGraphInterfaceKeyMap result: the index wins (an alias can be renamed between the
    # tool's run and the lookup), then the name. $null when -KeyMap is $null or neither is found.
    param(
        $KeyMap,

        $Index,

        [string]
        $Name
    )

    if (-not $KeyMap) { return $null }
    if ($null -ne $Index -and "$Index" -ne '' -and $KeyMap.ByIndex.ContainsKey("$Index")) { return $KeyMap.ByIndex["$Index"] }
    if ($Name -and $KeyMap.ByName.ContainsKey($Name)) { return $KeyMap.ByName[$Name] }
    $null
}
