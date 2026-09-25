<#
.SYNOPSIS
    ZeroTouch peripherals: pick the devices plugged into this machine and install them.

.DESCRIPTION
    Without parameters a touch-friendly window is shown (one receipt printer + any other devices).
    Every device lives in its own folder with an install.ps1; see devices.json and README.md.
    The chosen receipt printer is always published as the queue "XP-80C" and made the default printer.

.EXAMPLE
    .\Peripherals.ps1
    .\Peripherals.ps1 -Install xprinter-q260, hanel-hn212
#>
param(
    [string[]] $Install = @(),
    [string] $PortName = '',
    [switch] $AutoDetect
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Elevate (the tool installs drivers) ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$($MyInvocation.MyCommand.Path)`"")
        if ($Install) { $arguments += @('-Install', ($Install -join ',')) }
        if ($PortName) { $arguments += @('-PortName', $PortName) }
        if ($AutoDetect) { $arguments += @('-AutoDetect') }
        Start-Process -FilePath 'powershell.exe' -Verb 'RunAs' -ArgumentList $arguments
        return
    } catch {
        Write-Warning "Khong the tu dong nang quyen Administrator ($($_.Exception.Message)). Tiep tuc chay..."
    }
}


. (Join-Path $Root 'lib.ps1')
$devices = Get-Content -LiteralPath (Join-Path $Root 'devices.json') -Raw | ConvertFrom-Json
$logDir = 'C:\ZeroTouch\logs'
$null = New-Item -ItemType Directory -Force -Path $logDir
$logFile = Join-Path $logDir ("peripherals-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Install-Devices([string[]] $Ids, [scriptblock] $Write) {
    $failed = @()
    foreach ($id in $Ids) {
        $device = $devices | Where-Object { $_.id -eq $id }
        if (-not $device) { & $Write "[FAIL] ${id}: khong co trong devices.json"; $failed += $id; continue }
        & $Write "=== $($device.name) ==="
        $dir = Join-Path $Root $device.id
        try {
            $scriptArgs = @{ Dir = $dir }
            if ($device.group -eq 'printer' -and $PortName) { $scriptArgs.PortName = $PortName }
            foreach ($line in @(& (Join-Path $dir 'install.ps1') @scriptArgs 2>&1)) { & $Write "  $line" }
            & $Write "[OK] $($device.name)"
        } catch {
            & $Write "[FAIL] $($device.name): $($_.Exception.Message)"
            $failed += $id
        }
    }
    return $failed
}

function Get-DetectedDevices {
    $pnp = @(Get-PnpDevice -PresentOnly -ErrorAction 'SilentlyContinue')
    $pnpText = ($pnp | ForEach-Object { "$($_.FriendlyName) $($_.InstanceId) $($_.HardwareID)" }) -join "`n"
    $usbPrinterPort = @(Get-ConnectedUsbPrinterPort) | Select-Object -First 1

    $detected = @()
    foreach ($entry in $devices) {
        $matched = $false
        if ($entry.patterns) {
            foreach ($pat in $entry.patterns) {
                if ($pnpText -match [regex]::Escape($pat)) {
                    $matched = $true
                    break
                }
            }
        }
        if ($matched) {
            $detected += $entry.id
        }
    }

    # Neu co cong may in USB dang cam ma chua match duoc may in cu the nao,
    # mac dinh dung Xprinter Q260 (XP-80C) - dong may in pho bien nhat cua GoodM kiosk
    if ($usbPrinterPort) {
        $hasPrinter = $detected | Where-Object {
            $id = $_
            ($devices | Where-Object { $_.id -eq $id -and $_.group -eq 'printer' })
        }
        if (-not $hasPrinter) {
            $detected += 'xprinter-q260'
        }
    }

    return @($detected | Select-Object -Unique)
}

# --- Command-line mode ---
if ($Install) {
    $ids = $Install | ForEach-Object { $_ -split ',' } | Where-Object { $_ }
    $write = { param($text) Write-Host $text; Add-Content -LiteralPath $logFile -Value $text }
    $failed = Install-Devices $ids $write
    & $write "Log: $logFile"
    exit $(if ($failed) { 1 } else { 0 })
}

# --- Auto-detect mode ---
if ($AutoDetect) {
    $ids = Get-DetectedDevices
    $write = { param($text) Write-Host $text; Add-Content -LiteralPath $logFile -Value $text }
    if ($ids) {
        & $write "Phat hien thiet bi ngoai vi dang cam: $($ids -join ', ')"
        $failed = Install-Devices $ids $write
        & $write "Log: $logFile"
        exit $(if ($failed) { 1 } else { 0 })
    } else {
        & $write "Khong phat hien thiet bi ngoai vi nao dang cam."
        exit 0
    }
}

# --- Window (pre-select detected devices) ---
$detectedIds = Get-DetectedDevices
$detectedPrinter = $detectedIds | Where-Object {
    $id = $_
    ($devices | Where-Object { $_.id -eq $id -and $_.group -eq 'printer' })
} | Select-Object -First 1

Add-Type -AssemblyName 'System.Windows.Forms', 'System.Drawing'
[System.Windows.Forms.Application]::EnableVisualStyles()
$font = New-Object System.Drawing.Font('Segoe UI', 14)
$bold = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'ZeroTouch - Thiet bi ngoai vi'
$workArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Size = New-Object System.Drawing.Size([math]::Min(900, $workArea.Width), [math]::Min(860, $workArea.Height))
$form.StartPosition = 'CenterScreen'
$form.Font = $font
$form.AutoScroll = $true

$y = 15
function Add-Label([string] $text) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text; $label.Font = $bold; $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(20, $script:y)
    $form.Controls.Add($label)
    $script:y += 40
}

Add-Label "MAY IN HOA DON (chon 1) - ten may in: $PosQueueName"
$printerPanel = New-Object System.Windows.Forms.Panel
$printerPanel.Location = New-Object System.Drawing.Point(20, $y)
$printerPanel.Size = New-Object System.Drawing.Size(840, 50)
$form.Controls.Add($printerPanel)
$radios = @()
$x = 0
foreach ($entry in @([pscustomobject] @{ id = ''; name = 'Khong' }) + @($devices | Where-Object { $_.group -eq 'printer' })) {
    $radio = New-Object System.Windows.Forms.RadioButton
    $radio.Text = $entry.name; $radio.Tag = $entry.id; $radio.AutoSize = $true
    $radio.Location = New-Object System.Drawing.Point($x, 8)
    if ($detectedPrinter) {
        $radio.Checked = ($entry.id -eq $detectedPrinter)
    } else {
        $radio.Checked = ($entry.id -eq '')
    }
    $printerPanel.Controls.Add($radio)
    $radios += $radio
    $x += 200
}
$y += 65

Add-Label 'THIET BI KHAC (chon nhung thiet bi dang cam)'
$checks = @()
foreach ($entry in $devices | Where-Object { $_.group -ne 'printer' }) {
    $check = New-Object System.Windows.Forms.CheckBox
    $check.Text = $entry.name; $check.Tag = $entry.id; $check.AutoSize = $true
    $check.Location = New-Object System.Drawing.Point(30, $y)
    if ($detectedIds -contains $entry.id) {
        $check.Checked = $true
    }
    $form.Controls.Add($check)
    $checks += $check
    $y += 42
}
$y += 10


$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = 'Cai dat'; $installButton.Font = $bold
$installButton.Size = New-Object System.Drawing.Size(200, 60)
$installButton.Location = New-Object System.Drawing.Point(20, $y)
$form.Controls.Add($installButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = 'Dong'
$closeButton.Size = New-Object System.Drawing.Size(200, 60)
$closeButton.Location = New-Object System.Drawing.Point(240, $y)
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)
$y += 75

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'
$log.Font = New-Object System.Drawing.Font('Consolas', 11)
$log.Location = New-Object System.Drawing.Point(20, $y)
$log.Size = New-Object System.Drawing.Size(840, 200)
$form.Controls.Add($log)

$installButton.Add_Click({
    $ids = @($radios | Where-Object { $_.Checked -and $_.Tag } | ForEach-Object { $_.Tag }) +
        @($checks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if (-not $ids) { $log.AppendText("Chua chon thiet bi nao.`r`n"); return }
    $installButton.Enabled = $false; $closeButton.Enabled = $false
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $write = {
        param($text)
        $log.AppendText("$text`r`n")
        Add-Content -LiteralPath $logFile -Value $text
        [System.Windows.Forms.Application]::DoEvents()
    }
    $failed = Install-Devices $ids $write
    & $write $(if ($failed) { "XONG - co loi: $($failed -join ', ')" } else { 'XONG - tat ca thanh cong' })
    & $write "Log: $logFile"
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    $installButton.Enabled = $true; $closeButton.Enabled = $true
})

[void] $form.ShowDialog()
