# Offline drivers with Snappy Driver Installer Origin (\AutoInstaller\sdio).
param($Context)

$sdioDir = Join-Path $Context.Root 'sdio'
$sdio = Get-ChildItem -LiteralPath $sdioDir -Filter 'SDIO_x64_R*.exe' -ErrorAction 'SilentlyContinue' |
    Sort-Object -Property 'Name' -Descending |
    Select-Object -First 1
if (-not $sdio) {
    return @{ Status = 'SKIP'; Detail = "SDIO not found in $sdioDir" }
}

# The second pass picks up devices that only appear once chipset/USB drivers are in place.
foreach ($pass in 1, 2) {
    Write-Host "SDIO pass $pass - $($sdio.Name)"
    $process = Start-Process -FilePath $sdio.FullName -WorkingDirectory $sdio.DirectoryName -Wait -PassThru `
        -ArgumentList @('-autoinstall', '-autoclose', '-license', '-norestorepnt')
    Write-Host "SDIO exit code $($process.ExitCode)"
    pnputil.exe /scan-devices | Out-Host
    Start-Sleep -Seconds 10
}

$missing = @(Get-PnpDevice -PresentOnly -ErrorAction 'SilentlyContinue' | Where-Object { $_.Status -ne 'OK' })
return @{ Status = 'OK'; Detail = "$($sdio.Name), $($missing.Count) device(s) still without driver" }
