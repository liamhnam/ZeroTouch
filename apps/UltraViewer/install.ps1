# UltraViewer: silent Inno Setup install, then read the machine ID for inventory.csv.
param([string] $AppDir, $Context)

$setup = Get-ChildItem -LiteralPath $AppDir -Filter 'UltraViewer_setup*.exe' |
    Sort-Object -Property 'Name' -Descending |
    Select-Object -First 1
if (-not $setup) { throw "UltraViewer_setup*.exe not found in $AppDir" }

$process = Start-Process -FilePath $setup.FullName -Wait -PassThru `
    -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-')
if ($process.ExitCode -ne 0) { throw "$($setup.Name) exit code $($process.ExitCode)" }

$exe = @("${env:ProgramFiles(x86)}\UltraViewer\UltraViewer_Desktop.exe", "$env:ProgramFiles\UltraViewer\UltraViewer_Desktop.exe") |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if (-not $exe) { throw 'UltraViewer_Desktop.exe not found after setup' }
"Installed $exe"

# The ID is assigned by UltraViewer's server once the machine is online and stored in
# HKLM\SOFTWARE\WOW6432Node\UltraViewer\PreferID (verified with 6.6.133).
if (-not (Get-Process -Name 'UltraViewer_Desktop' -ErrorAction 'SilentlyContinue')) {
    Start-Process -FilePath $exe
}
$id = ''
# Chi doi lay ID khi may da co ket noi Internet, toi da 15 giay (tranh treo 60 giay neu offline)
if ($Context.Inventory.WifiStatus -eq 'CONNECTED') {
    for ($i = 0; $i -lt 5 -and -not $id; $i++) {
        Start-Sleep -Seconds 3
        $id = [string] (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\UltraViewer' -ErrorAction 'SilentlyContinue').PreferID
    }
}
$Context.Inventory.UltraViewerID = $id
"UltraViewer ID: $(if ($id) { $id } else { 'not found' })"

