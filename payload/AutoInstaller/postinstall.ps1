# ZeroTouch post-install payload.
# Started from the USB drive by the first-logon script of autounattend.xml, elevated.
# Runs every steps\*.ps1 in name order, never stops on a failure, then writes one
# inventory.csv row, copies the logs to the USB drive and reboots once.
#
# Step contract: param($Context); return @{ Status = 'OK'|'SKIP'|'FAIL'; Detail = '...' }
# (throwing counts as FAIL). Steps may add columns through $Context.Inventory.

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LocalLogDir = 'C:\AutoInstaller\logs'
$null = New-Item -ItemType Directory -Force -Path $LocalLogDir
Start-Transcript -LiteralPath (Join-Path $LocalLogDir "postinstall-$Stamp.log") -Append | Out-Null

$Context = @{
    Root      = $Root
    Inventory = [ordered] @{ WifiAdapter = ''; Wifi5GHz = ''; WifiStatus = ''; UltraViewerID = '' }
}

function Test-StepResult($Item) {
    return ($Item -is [hashtable]) -and $Item.ContainsKey('Status')
}

# --- Steps ---
$results = @()
foreach ($step in Get-ChildItem -LiteralPath (Join-Path $Root 'steps') -Filter '*.ps1' | Sort-Object -Property 'Name') {
    Write-Host ''
    Write-Host "=== $($step.BaseName) ===" -ForegroundColor Cyan
    $started = Get-Date
    try {
        $output = @(& $step.FullName -Context $Context)
        $output | Where-Object { -not (Test-StepResult $_) } | Out-Host
        $outcome = $output | Where-Object { Test-StepResult $_ } | Select-Object -Last 1
        if ($outcome) { $status = $outcome.Status; $detail = $outcome.Detail } else { $status = 'OK'; $detail = '' }
    } catch {
        $status = 'FAIL'
        $detail = $_.Exception.Message
    }
    $color = @{ OK = 'Green'; SKIP = 'Yellow'; FAIL = 'Red' }[$status]
    Write-Host "[$status] $($step.BaseName) $detail" -ForegroundColor $color
    $results += [pscustomobject] @{
        Step    = $step.BaseName
        Status  = $status
        Detail  = $detail
        Seconds = [int] ((Get-Date) - $started).TotalSeconds
    }
}

# --- Inventory row ---
$bios = Get-CimInstance -ClassName 'Win32_BIOS'
$system = Get-CimInstance -ClassName 'Win32_ComputerSystem'
$os = Get-CimInstance -ClassName 'Win32_OperatingSystem'
$cpu = Get-CimInstance -ClassName 'Win32_Processor' | Select-Object -First 1
$diskBytes = (Get-CimInstance -ClassName 'Win32_DiskDrive' | Where-Object { $_.InterfaceType -ne 'USB' } |
    Measure-Object -Property 'Size' -Sum).Sum
$macs = Get-CimInstance -ClassName 'Win32_NetworkAdapter' -Filter 'PhysicalAdapter = TRUE' |
    Where-Object { $_.MACAddress } | ForEach-Object { $_.MACAddress }
$missing = @(Get-PnpDevice -PresentOnly -ErrorAction 'SilentlyContinue' | Where-Object { $_.Status -ne 'OK' })
$failed = @($results | Where-Object { $_.Status -eq 'FAIL' })

$row = [ordered] @{
    FinishedAt     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    InstalledAt    = $os.InstallDate.ToString('yyyy-MM-dd HH:mm:ss')
    Result         = $(if ($failed) { 'FAIL' } else { 'OK' })
    FailedSteps    = ($failed | ForEach-Object { $_.Step }) -join '; '
    ComputerName   = $env:COMPUTERNAME
    Serial         = ([string] $bios.SerialNumber).Trim()
    Manufacturer   = ([string] $system.Manufacturer).Trim()
    Model          = ([string] $system.Model).Trim()
    CPU            = ([string] $cpu.Name).Trim()
    RAM_GB         = [math]::Round($system.TotalPhysicalMemory / 1GB, 1)
    Disk_GB        = [math]::Round($diskBytes / 1GB)
    MAC            = $macs -join '; '
    MissingDrivers = $missing.Count
    MissingList    = ($missing | ForEach-Object { "$($_.Class):$($_.FriendlyName)" }) -join '; '
}
foreach ($key in $Context.Inventory.Keys) { $row[$key] = $Context.Inventory[$key] }
$inventory = Join-Path $Root 'inventory.csv'
try {
    [pscustomobject] $row | Export-Csv -LiteralPath $inventory -Append -NoTypeInformation -Encoding 'UTF8'
} catch {
    Write-Host "Could not write $inventory : $($_.Exception.Message)" -ForegroundColor Red
}
$results | Format-Table -AutoSize | Out-String -Width 300 | Write-Host

# --- Desktop note ---
$lines = @(
    "ZeroTouch $($row.Result) - $($row.FinishedAt) - $env:COMPUTERNAME"
    "Log: $LocalLogDir va USB \AutoInstaller\logs\$env:COMPUTERNAME-$Stamp"
    ''
)
$lines += $results | ForEach-Object { "[$($_.Status)] $($_.Step) $($_.Detail)" }
$lines += '', "Thiet bi chua co driver: $($missing.Count)"
$lines += $missing | ForEach-Object { "  [$($_.Status)] $($_.Class) - $($_.FriendlyName)" }
$note = $(if ($failed) { 'LOI.txt' } else { 'HOAN-TAT.txt' })
$lines | Set-Content -LiteralPath (Join-Path 'C:\Users\Public\Desktop' $note) -Encoding 'UTF8'

Stop-Transcript | Out-Null

# --- Logs to the USB drive, one folder per machine ---
$usbLogDir = Join-Path $Root "logs\$env:COMPUTERNAME-$Stamp"
$null = New-Item -ItemType Directory -Force -Path $usbLogDir -ErrorAction 'SilentlyContinue'
Copy-Item -Path "$LocalLogDir\*", 'C:\Windows\Setup\Scripts\*.log', 'C:\Windows\Panther\setupact.log', 'C:\Windows\Panther\setuperr.log' `
    -Destination $usbLogDir -ErrorAction 'SilentlyContinue'

# --- Final reboot so every driver is fully loaded; auto-logon lands on the desktop ready for use ---
shutdown.exe /r /t 5 /c 'ZeroTouch: Khoi dong lai lan cuoi - San sang su dung'

