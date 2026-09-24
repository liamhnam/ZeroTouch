# Wi-Fi: import every \AutoInstaller\wifi\*.xml profile, connect to the first one and check Internet access.
# Runs after the driver step because the USB Wi-Fi adapter has no driver before that.
param($Context)

$profiles = @(Get-ChildItem -LiteralPath (Join-Path $Context.Root 'wifi') -Filter '*.xml' -ErrorAction 'SilentlyContinue')
if (-not $profiles) {
    return @{ Status = 'SKIP'; Detail = 'no Wi-Fi profile on the USB drive' }
}

$drivers = netsh.exe wlan show drivers | Out-String
$adapter = [regex]::Match($drivers, '(?m)^\s*Driver\s*:\s*(.+?)\s*$').Groups[1].Value
if (-not $adapter) {
    $Context.Inventory.WifiStatus = 'NO_ADAPTER'
    return @{ Status = 'FAIL'; Detail = 'no Wi-Fi adapter with a working driver' }
}
$radios = [regex]::Match($drivers, '(?m)^\s*Radio types supported\s*:\s*(.+?)\s*$').Groups[1].Value
$Context.Inventory.WifiAdapter = $adapter
$Context.Inventory.Wifi5GHz = $(if ($radios -match '802\.11(a|ac|ax)\b') { 'YES' } else { 'NO' })
Write-Host "Adapter: $adapter ($radios)"

foreach ($file in $profiles) {
    netsh.exe wlan add profile filename="$($file.FullName)" user=all | Out-Host
}
$ssid = ([xml] (Get-Content -LiteralPath $profiles[0].FullName -Raw)).WLANProfile.name
netsh.exe wlan connect name="$ssid" | Out-Host

$connected = $false
for ($i = 0; $i -lt 30 -and -not $connected; $i++) {
    Start-Sleep -Seconds 2
    $state = netsh.exe wlan show interfaces | Out-String
    $connected = ($state -match '(?m)^\s*State\s*:\s*connected\s*$') -and
        ($state -match "(?m)^\s*SSID\s*:\s*$([regex]::Escape($ssid))\s*$")
}
if (-not $connected) {
    $Context.Inventory.WifiStatus = 'NOT_CONNECTED'
    return @{ Status = 'FAIL'; Detail = "could not connect to $ssid (5GHz: $($Context.Inventory.Wifi5GHz))" }
}

$online = $false
for ($i = 0; $i -lt 15 -and -not $online; $i++) {
    $online = Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet
    if (-not $online) { Start-Sleep -Seconds 2 }
}
if (-not $online) {
    $Context.Inventory.WifiStatus = 'NO_INTERNET'
    return @{ Status = 'FAIL'; Detail = "connected to $ssid but no Internet" }
}
$Context.Inventory.WifiStatus = 'CONNECTED'
return @{ Status = 'OK'; Detail = "connected to $ssid" }
