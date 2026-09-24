# Applications: runs \AutoInstaller\apps\<name>\install.ps1 -AppDir <folder> -Context $Context for each app.
# An app installer throws on failure; one failing app does not stop the others.
param($Context)

$apps = @(Get-ChildItem -LiteralPath (Join-Path $Context.Root 'apps') -Directory -ErrorAction 'SilentlyContinue' |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') } |
    Sort-Object -Property 'Name')
if (-not $apps) {
    return @{ Status = 'SKIP'; Detail = 'no apps on the USB drive' }
}

$failed = @()
foreach ($app in $apps) {
    Write-Host "Installing $($app.Name)"
    try {
        & (Join-Path $app.FullName 'install.ps1') -AppDir $app.FullName -Context $Context | Out-Host
        Write-Host "[OK] $($app.Name)"
    } catch {
        $failed += $app.Name
        Write-Host "[FAIL] $($app.Name): $($_.Exception.Message)"
    }
}
if ($failed) {
    return @{ Status = 'FAIL'; Detail = "failed: $($failed -join ', ')" }
}
return @{ Status = 'OK'; Detail = ($apps | ForEach-Object { $_.Name }) -join ', ' }
