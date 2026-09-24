# Evaluated by Windows Setup; must return a valid computer name (max 15 characters).
# GOODM-<last 9 characters of the BIOS serial>, or GOODM-<last 6 of the onboard MAC>
# when the serial is a placeholder such as "To be filled by O.E.M.".
$prefix = 'GOODM-'
$maxSuffix = 15 - $prefix.Length

$serial = [string] (Get-CimInstance -ClassName 'Win32_BIOS').SerialNumber
$placeholder = '^\s*(to be filled|default string|system serial number|chassis serial number|not applicable|none|n/?a|oem|0+|1234567890?|123456789|x+)\s*$'
$suffix = ($serial -replace '[^A-Za-z0-9]', '').ToUpper()
if ($serial -match $placeholder -or $suffix.Length -lt 4) {
    $adapter = Get-CimInstance -ClassName 'Win32_NetworkAdapter' -Filter 'PhysicalAdapter = TRUE' |
        Where-Object { $_.MACAddress } |
        Sort-Object -Property @{ Expression = { $_.PNPDeviceID -notlike 'PCI\*' } }, 'DeviceID' |
        Select-Object -First 1
    if ($adapter) {
        $mac = $adapter.MACAddress -replace '[^A-Fa-f0-9]', ''
        $suffix = $mac.Substring($mac.Length - 6).ToUpper()
    } else {
        $suffix = '{0:X6}' -f (Get-Random -Minimum 0 -Maximum 0xFFFFFF)
    }
}
if ($suffix.Length -gt $maxSuffix) {
    $suffix = $suffix.Substring($suffix.Length - $maxSuffix)
}
return "$prefix$suffix"
