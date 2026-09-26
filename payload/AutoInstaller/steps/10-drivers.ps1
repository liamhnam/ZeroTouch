# Driver installation: Priority 1 = Pre-staged INF drivers (Chipset, Graphics, Wi-Fi), Priority 2 = SDIO fallback.
param($Context)

$installedInfs = 0
# Check for staged driver packages
$driverSources = @(
    (Join-Path $Context.Root 'drivers'),
    (Join-Path $Context.Root '..\drivers\inject'),
    (Join-Path $Context.Root '..\$WinPEDriver$')
)

foreach ($dir in $driverSources) {
    if (Test-Path -LiteralPath $dir) {
        $infs = @(Get-ChildItem -LiteralPath $dir -Filter '*.inf' -Recurse -ErrorAction 'SilentlyContinue')
        if ($infs.Count -gt 0) {
            Write-Host "Installing $($infs.Count) staged driver INF(s) from $dir..." -ForegroundColor Cyan
            & pnputil.exe /add-driver "$dir\*.inf" /subdirs /install | Out-Host
            $installedInfs += $infs.Count
        }
    }
}

if ($installedInfs -gt 0) {
    pnputil.exe /scan-devices | Out-Host
}

$sdioDir = Join-Path $Context.Root 'sdio'
$sdio = Get-ChildItem -LiteralPath $sdioDir -Filter 'SDIO_x64_R*.exe' -ErrorAction 'SilentlyContinue' |
    Sort-Object -Property 'Name' -Descending |
    Select-Object -First 1

$missing = @(Get-PnpDevice -PresentOnly -ErrorAction 'SilentlyContinue' | Where-Object { $_.Status -ne 'OK' })

if (-not $sdio) {
    if ($installedInfs -gt 0) {
        return @{ Status = 'OK'; Detail = "Installed $installedInfs INF driver(s); $($missing.Count) device(s) remaining" }
    }
    return @{ Status = 'SKIP'; Detail = "No SDIO or staged driver packages found" }
}

$hasBasicDisplay = [bool](Get-PnpDevice -Class 'Display' -PresentOnly -ErrorAction 'SilentlyContinue' |
    Where-Object { $_.FriendlyName -match 'Basic Display|Standard VGA' })

if ($missing.Count -eq 0 -and -not $hasBasicDisplay) {
    Write-Host "All devices already working with manufacturer drivers. SDIO skipped." -ForegroundColor Green
    return @{ Status = 'OK'; Detail = "All devices working. SDIO skipped." }
}

# Run SDIO if missing devices or generic basic display remain
$statusReason = if ($hasBasicDisplay) {
    "$($missing.Count) device(s) and VGA (Basic Display) remaining"
} else {
    "$($missing.Count) device(s) remaining"
}
Write-Host "SDIO pass - $($sdio.Name) (resolving $statusReason, fast extract to SSD)..." -ForegroundColor Cyan

# Create fast scratch directory on SSD to eliminate USB 2.0/3.0 write bottleneck
$fastTemp = 'C:\ZeroTouch\temp'
$null = New-Item -ItemType Directory -Force -Path $fastTemp -ErrorAction 'SilentlyContinue'

$sdioArgs = @(
    '-autoinstall',
    '-autoclose',
    '-license',
    '-norestorepnt',
    "-extractdir:$fastTemp",
    '-nogui'
)

$process = Start-Process -FilePath $sdio.FullName -WorkingDirectory $sdio.DirectoryName -Wait -PassThru `
    -ArgumentList $sdioArgs
Write-Host "SDIO exit code $($process.ExitCode)"

# Cleanup temp extract folder to free SSD space
Remove-Item -LiteralPath $fastTemp -Recurse -Force -ErrorAction 'SilentlyContinue'

pnputil.exe /scan-devices | Out-Host

$hasBasicDisplay = [bool](Get-PnpDevice -Class 'Display' -PresentOnly -ErrorAction 'SilentlyContinue' |
    Where-Object { $_.FriendlyName -match 'Basic Display|Standard VGA' })
$missing = @(Get-PnpDevice -PresentOnly -ErrorAction 'SilentlyContinue' | Where-Object { $_.Status -ne 'OK' })

$detail = "$($sdio.Name), $($missing.Count) device(s) still without driver"
if ($hasBasicDisplay) {
    $detail += " (VGA: Basic Display)"
} else {
    $gpu = Get-PnpDevice -Class 'Display' -PresentOnly -ErrorAction 'SilentlyContinue' | Select-Object -First 1
    if ($gpu) { $detail += " (VGA: $($gpu.FriendlyName))" }
}
return @{ Status = 'OK'; Detail = $detail }
