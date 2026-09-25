# Peripherals tool: copy \AutoInstaller\peripherals to C:\ZeroTouch\Peripherals and put a shortcut on the
# desktop. The technician runs it and ticks the devices that are plugged in (it works without the USB drive).
param($Context)

$source = Join-Path $Context.Root 'peripherals'
if (-not (Test-Path -LiteralPath (Join-Path $source 'Peripherals.ps1'))) {
    return @{ Status = 'SKIP'; Detail = 'no peripherals folder on the USB drive' }
}

$target = 'C:\ZeroTouch\Peripherals'
robocopy.exe $source $target /E /R:1 /W:1 /NFL /NDL /NJH /NP | Out-Host
if ($LASTEXITCODE -ge 8) { return @{ Status = 'FAIL'; Detail = "copy to $target failed (robocopy $LASTEXITCODE)" } }

$shell = New-Object -ComObject 'WScript.Shell'
$link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Thiet bi ngoai vi.lnk'))
$link.TargetPath = 'powershell.exe'
$link.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$target\Peripherals.ps1`""
$link.WorkingDirectory = $target
$link.IconLocation = 'shell32.dll,16'
$link.Save()

# --- Auto-detect and install plugged-in peripherals ---
$periphScript = Join-Path $target 'Peripherals.ps1'
$configFile = Join-Path $target 'config.txt'

$installedDetail = "da tao shortcut Desktop (khong co ngoai vi cam san)"
if (Test-Path -LiteralPath $configFile) {
    $preset = (Get-Content -LiteralPath $configFile -Raw).Trim()
    if ($preset) {
        Write-Host "Cai dat thiet bi ngoai vi theo cau hinh: $preset"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$periphScript" -Install $preset | Out-Host
    }
} else {
    Write-Host "Tu dong quet thiet bi ngoai vi USB dang cam..."
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$periphScript" -AutoDetect | Out-Host
}

# Doc log de lay danh sach thiet bi da cai thanh cong
$log = Get-ChildItem -LiteralPath 'C:\ZeroTouch\logs' -Filter 'peripherals-*.log' -ErrorAction 'SilentlyContinue' |
    Sort-Object -Property 'LastWriteTime' -Descending | Select-Object -First 1

if ($log) {
    $installed = @(Get-Content -LiteralPath $log.FullName -ErrorAction 'SilentlyContinue' |
        Where-Object { $_ -match '^\[OK\]\s*(.+)$' } | ForEach-Object { $Matches[1] })
    if ($installed) {
        $installedDetail = "Tu dong cai: $($installed -join ', ')"
    }
}

return @{ Status = 'OK'; Detail = $installedDetail }

