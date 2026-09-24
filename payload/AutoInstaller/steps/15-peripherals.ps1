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
return @{ Status = 'OK'; Detail = "$target + desktop shortcut" }
