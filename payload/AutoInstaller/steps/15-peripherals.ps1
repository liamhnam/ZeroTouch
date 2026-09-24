# Peripheral drivers (phase 2): \AutoInstaller\peripherals\install.ps1 -Root <folder>.
param($Context)

$dir = Join-Path $Context.Root 'peripherals'
$installer = Join-Path $dir 'install.ps1'
if (-not (Test-Path -LiteralPath $installer)) {
    return @{ Status = 'SKIP'; Detail = 'not configured yet' }
}

& $installer -Root $dir | Out-Host
return @{ Status = 'OK'; Detail = '' }
