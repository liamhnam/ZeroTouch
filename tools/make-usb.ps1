<#
.SYNOPSIS
    Build a ZeroTouch USB drive: 1 USB, 1 Windows ISO, zero-touch install.

.DESCRIPTION
    THE WHOLE USB DRIVE IS ERASED. USB layout (FAT32, MBR - boots on any UEFI firmware):
      <ISO contents>            without install.* and the ISO's own autounattend.xml
      sources\install*.swm      install.esd exported to WIM (faster to apply), split under 4 GiB
      autounattend.xml          dist\autounattend.xml
      AutoInstaller\            payload\AutoInstaller (postinstall.ps1, steps)
      AutoInstaller\apps\       apps\<name> (folders that contain install.ps1)
      AutoInstaller\sdio\       drivers\sdio (only if SDIO is present)
      AutoInstaller\wifi\       Wi-Fi profile generated from secrets.env
      $WinPEDriver$\            drivers\inject (drivers added to Windows during setup, if any .inf)
    The converted image is cached in %LOCALAPPDATA%\ZeroTouch, so only the first run is slow.

.EXAMPLE
    .\tools\make-usb.ps1 -Iso 'D:\tiny11 23H2 x64.iso' -DiskNumber 2
#>
#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory)] [string] $Iso,
    [Parameter(Mandatory)] [int] $DiskNumber
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Label = 'ZEROTOUCH'
$Fat32Limit = 4GB - 1
$SwmSizeMB = 3800

function Invoke-Native([string] $File, [string[]] $Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE" }
}

function Copy-Tree([string] $From, [string] $To, [string[]] $ExcludeFiles = @()) {
    $arguments = @($From, $To, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NP')
    if ($ExcludeFiles) { $arguments += @('/XF') + $ExcludeFiles }
    & robocopy.exe @arguments | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy $From -> $To failed with exit code $LASTEXITCODE" }
}

function Read-Secrets([string] $Path) {
    $values = @{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*?)\s*$') { $values[$Matches[1]] = $Matches[2] }
        }
    }
    return $values
}

function New-WifiProfile([string] $Ssid, [string] $Password, [string] $Authentication) {
    $ssidXml = [System.Security.SecurityElement]::Escape($Ssid)
    $keyXml = [System.Security.SecurityElement]::Escape($Password)
    return @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$ssidXml</name>
    <SSIDConfig>
        <SSID><name>$ssidXml</name></SSID>
        <nonBroadcast>false</nonBroadcast>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>$Authentication</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$keyXml</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@
}

# --- Inputs ---
$Iso = (Resolve-Path -LiteralPath $Iso).Path
$answerFile = Join-Path $Root 'dist\autounattend.xml'
if (-not (Test-Path -LiteralPath $answerFile)) { throw "$answerFile is missing - run: python build.py" }
$secrets = Read-Secrets (Join-Path $Root 'secrets.env')
$hasSdio = [bool] (Get-ChildItem -LiteralPath (Join-Path $Root 'drivers\sdio') -Filter 'SDIO_x64_R*.exe' -ErrorAction 'SilentlyContinue')
$injectInfs = @(Get-ChildItem -LiteralPath (Join-Path $Root 'drivers\inject') -Filter '*.inf' -Recurse -ErrorAction 'SilentlyContinue')
$apps = @(Get-ChildItem -LiteralPath (Join-Path $Root 'apps') -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') })

# --- Safety: only ever touch a removable USB disk ---
$disk = Get-Disk -Number $DiskNumber
if ($disk.BusType -ne 'USB') { throw "Disk $DiskNumber is not a USB disk (BusType: $($disk.BusType))" }
if ($disk.IsBoot -or $disk.IsSystem) { throw "Disk $DiskNumber is a boot/system disk" }
if ($disk.Size -gt 256GB) { throw "Disk $DiskNumber is larger than 256 GB - refusing, is this really a USB stick?" }

$isoItem = Get-Item -LiteralPath $Iso
$cache = Join-Path $env:LOCALAPPDATA ("ZeroTouch\{0}-{1}-{2}" -f $isoItem.BaseName, $isoItem.Length, $isoItem.LastWriteTimeUtc.Ticks)
$null = New-Item -ItemType Directory -Force -Path $cache

$image = Mount-DiskImage -ImagePath $Iso -PassThru
try {
    $isoRoot = "$(($image | Get-Volume).DriveLetter):\"
    $sources = Join-Path $isoRoot 'sources'

    # --- Windows image: ESD -> WIM (cached), split into SWM when over the FAT32 limit ---
    $wim = Join-Path $cache 'install.wim'
    $esd = Join-Path $sources 'install.esd'
    $imageFiles = @()
    if (Test-Path -LiteralPath (Join-Path $sources 'install.swm')) {
        $imageFiles = @(Get-ChildItem -LiteralPath $sources -Filter 'install*.swm')
    } else {
        if (Test-Path -LiteralPath $esd) {
            if (-not (Test-Path -LiteralPath $wim)) {
                Write-Host 'Converting install.esd to install.wim (first run only, takes a while)...'
                Invoke-Native 'dism.exe' @('/Export-Image', "/SourceImageFile:$esd", '/SourceIndex:1',
                    "/DestinationImageFile:$wim.tmp", '/Compress:max', '/CheckIntegrity')
                Move-Item -LiteralPath "$wim.tmp" -Destination $wim
            }
        } else {
            $wim = Join-Path $sources 'install.wim'
            if (-not (Test-Path -LiteralPath $wim)) { throw 'The ISO has no sources\install.wim, install.esd or install.swm' }
        }
        if ((Get-Item -LiteralPath $wim).Length -le $Fat32Limit) {
            $imageFiles = @(Get-Item -LiteralPath $wim)
        } else {
            $swmDir = Join-Path $cache 'swm'
            if (-not (Test-Path -LiteralPath (Join-Path $swmDir 'install.swm'))) {
                Write-Host 'Splitting install.wim for FAT32...'
                Remove-Item -LiteralPath $swmDir -Recurse -Force -ErrorAction 'SilentlyContinue'
                $null = New-Item -ItemType Directory -Force -Path $swmDir
                Invoke-Native 'dism.exe' @('/Split-Image', "/ImageFile:$wim", "/SWMFile:$(Join-Path $swmDir 'install.swm')",
                    "/FileSize:$SwmSizeMB", '/CheckIntegrity')
            }
            $imageFiles = @(Get-ChildItem -LiteralPath $swmDir -Filter 'install*.swm')
        }
    }

    # --- FAT32 and capacity checks ---
    $payloadFiles = @(Get-ChildItem -LiteralPath $isoRoot -Recurse -File | Where-Object { $_.Name -notlike 'install.*' })
    $payloadFiles += $imageFiles
    foreach ($app in $apps) { $payloadFiles += Get-ChildItem -LiteralPath $app.FullName -Recurse -File }
    if ($hasSdio) { $payloadFiles += Get-ChildItem -LiteralPath (Join-Path $Root 'drivers\sdio') -Recurse -File }
    $tooBig = @($payloadFiles | Where-Object { $_.Length -gt $Fat32Limit })
    if ($tooBig) { throw "Files over 4 GiB cannot be stored on FAT32:`n$($tooBig.FullName -join "`n")" }
    $needed = ($payloadFiles | Measure-Object -Property 'Length' -Sum).Sum + 100MB
    $partitionSize = [math]::Min($disk.Size - 16MB, 32GB)   # Windows formats FAT32 only up to 32 GB
    if ($needed -gt $partitionSize) { throw ("Not enough space: need {0:N1} GB, have {1:N1} GB" -f ($needed / 1GB), ($partitionSize / 1GB)) }

    # --- Confirmation ---
    Write-Host ''
    Write-Host "ISO:    $Iso"
    Write-Host ("USB:    disk {0} - {1}, {2:N1} GB" -f $disk.Number, $disk.FriendlyName, ($disk.Size / 1GB))
    Write-Host "Image:  $(($imageFiles | ForEach-Object { $_.Name }) -join ', ')"
    Write-Host "Apps:   $(if ($apps) { ($apps | ForEach-Object { $_.Name }) -join ', ' } else { 'none' })"
    Write-Host "SDIO:   $(if ($hasSdio) { 'yes' } else { 'NO - drivers will not be installed (see drivers\sdio\README.md)' })"
    Write-Host "Wi-Fi:  $(if ($secrets.WIFI_SSID) { $secrets.WIFI_SSID } else { 'none (secrets.env missing)' })"
    Write-Host "Inject: $(if ($injectInfs) { ($injectInfs | ForEach-Object { $_.Directory.Name } | Sort-Object -Unique) -join ', ' } else { 'none' })"
    Write-Host ''
    $disk | Get-Partition -ErrorAction 'SilentlyContinue' | Format-Table -AutoSize PartitionNumber, DriveLetter, Size, Type
    $answer = Read-Host "ALL DATA on disk $DiskNumber will be erased. Type the disk number to continue"
    if ($answer -ne [string] $DiskNumber) { throw 'Aborted' }

    # --- Format ---
    if ((Get-Disk -Number $DiskNumber).PartitionStyle -ne 'RAW') {
        Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
    }
    Initialize-Disk -Number $DiskNumber -PartitionStyle 'MBR'
    $partition = New-Partition -DiskNumber $DiskNumber -Size $partitionSize -IsActive -AssignDriveLetter
    $null = Format-Volume -Partition $partition -FileSystem 'FAT32' -NewFileSystemLabel $Label -Confirm:$false
    $usb = "$((Get-Partition -DiskNumber $DiskNumber -PartitionNumber $partition.PartitionNumber).DriveLetter):\"

    # --- Copy ---
    Write-Host 'Copying Windows setup files...'
    Copy-Tree $isoRoot $usb @('install.esd', 'install.wim', 'install*.swm', 'autounattend.xml')
    Write-Host 'Copying Windows image...'
    foreach ($file in $imageFiles) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $usb 'sources') }
    Copy-Item -LiteralPath $answerFile -Destination (Join-Path $usb 'autounattend.xml')
    Copy-Tree (Join-Path $Root 'payload') $usb
    foreach ($app in $apps) { Copy-Tree $app.FullName (Join-Path $usb "AutoInstaller\apps\$($app.Name)") }
    if ($hasSdio) {
        Write-Host 'Copying SDIO...'
        Copy-Tree (Join-Path $Root 'drivers\sdio') (Join-Path $usb 'AutoInstaller\sdio') @('README.md', '.gitignore')
    }
    if ($injectInfs) {
        Copy-Tree (Join-Path $Root 'drivers\inject') (Join-Path $usb '$WinPEDriver$') @('README.md', '.gitignore')
    }
    if ($secrets.WIFI_SSID) {
        $wifiDir = Join-Path $usb 'AutoInstaller\wifi'
        $null = New-Item -ItemType Directory -Force -Path $wifiDir
        $auth = $(if ($secrets.WIFI_AUTH) { $secrets.WIFI_AUTH } else { 'WPA2PSK' })
        $fileName = ($secrets.WIFI_SSID -replace '[^A-Za-z0-9_.-]', '_') + '.xml'
        New-WifiProfile $secrets.WIFI_SSID $secrets.WIFI_PASSWORD $auth |
            Set-Content -LiteralPath (Join-Path $wifiDir $fileName) -Encoding 'UTF8'
    }
} finally {
    Dismount-DiskImage -ImagePath $Iso | Out-Null
}

Write-Host ''
Write-Host "Done. USB '$Label' ($usb) is ready - boot the target machine from it in UEFI mode." -ForegroundColor Green
