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

if ($missing.Count -eq 0) {
    Write-Host "All devices already working. SDIO skipped." -ForegroundColor Green
    return @{ Status = 'OK'; Detail = "All devices working. SDIO skipped." }
}

# Run SDIO if missing devices remain
Write-Host "SDIO pass - $($sdio.Name) (resolving $($missing.Count) remaining devices)"
$process = Start-Process -FilePath $sdio.FullName -WorkingDirectory $sdio.DirectoryName -Wait -PassThru `
    -ArgumentList @('-autoinstall', '-autoclose', '-license', '-norestorepnt')
Write-Host "SDIO exit code $($process.ExitCode)"
pnputil.exe /scan-devices | Out-Host

$missing = @(Get-PnpDevice -PresentOnly -ErrorAction 'SilentlyContinue' | Where-Object { $_.Status -ne 'OK' })
return @{ Status = 'OK'; Detail = "$($sdio.Name), $($missing.Count) device(s) still without driver" }
