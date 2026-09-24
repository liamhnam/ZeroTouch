# UltraViewer: silent Inno Setup install, then best-effort lookup of the machine ID.
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

# UltraViewer documents no way to read the ID. It receives one from its server once online,
# so start it and look for an ID-like value in its settings files and registry keys.
function Find-UltraViewerId {
    $idPattern = '^\s*\d{3}\s?\d{3}\s?\d{3,4}\s*$'
    $folders = @((Split-Path -Parent $exe), "$env:APPDATA\UltraViewer", "$env:ProgramData\UltraViewer")
    foreach ($file in Get-ChildItem -LiteralPath $folders -Include '*.ini', '*.cfg', '*.txt', '*.xml' -Recurse -ErrorAction 'SilentlyContinue') {
        foreach ($line in Get-Content -LiteralPath $file.FullName -ErrorAction 'SilentlyContinue') {
            $match = [regex]::Match($line, '(?i)\bid\b[^=:]*[=:]\s*"?([\d ]{9,13})"?')
            if ($match.Success -and $match.Groups[1].Value -match $idPattern) { return ($match.Groups[1].Value -replace ' ', '') }
        }
    }
    $roots = @('HKCU:\Software\UltraViewer', 'HKLM:\SOFTWARE\WOW6432Node\UltraViewer', 'HKLM:\SOFTWARE\UltraViewer') |
        Where-Object { Test-Path -LiteralPath $_ }
    $keys = @($roots) + @(Get-ChildItem -LiteralPath $roots -Recurse -ErrorAction 'SilentlyContinue' | ForEach-Object { $_.PSPath })
    foreach ($key in $keys) {
        $item = Get-ItemProperty -LiteralPath $key -ErrorAction 'SilentlyContinue'
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Name -match '(?i)id' -and [string] $property.Value -match $idPattern) {
                return ([string] $property.Value -replace ' ', '')
            }
        }
    }
    return ''
}

if (-not (Get-Process -Name 'UltraViewer_Desktop' -ErrorAction 'SilentlyContinue')) {
    Start-Process -FilePath $exe
}
$id = ''
for ($i = 0; $i -lt 12 -and -not $id; $i++) {
    Start-Sleep -Seconds 5
    $id = Find-UltraViewerId
}
$Context.Inventory.UltraViewerID = $id
"UltraViewer ID: $(if ($id) { $id } else { 'not found' })"
