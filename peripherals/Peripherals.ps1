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

# --- Modern Touch-Friendly WPF GUI ---
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$workHeight = [Math]::Max(650, [Math]::Min(860, [System.Windows.SystemParameters]::WorkArea.Height - 40))

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ZeroTouch POS - Thiet bi Ngoai vi"
        Width="960" Height="$workHeight"
        MinWidth="800" MinHeight="600"
        WindowStartupLocation="CenterScreen"
        Background="#0F172A" Foreground="#F8FAFC"
        FontFamily="Segoe UI" FontSize="14">

    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Top Header Card -->
        <Border Grid.Row="0" Background="#1E293B" CornerRadius="14" Padding="20,16" Margin="0,0,0,16"
                BorderBrush="#334155" BorderThickness="1.5">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="[POS]" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,10,0" VerticalAlignment="Center"/>
                        <TextBlock Text="THIET BI NGOAI VI KIOSK / POS" FontSize="20" FontWeight="Bold"
                                   Foreground="#38BDF8" VerticalAlignment="Center"/>
                    </StackPanel>
                    <TextBlock Text="Cham truc tiep vao cac the de chon thiet bi. Thiet bi dang cam USB se duoc danh dau xanh va chon san."
                               FontSize="13" Foreground="#94A3B8" Margin="0,6,0,0"/>
                </StackPanel>

                <Border Grid.Column="1" Background="#0F172A" CornerRadius="10" Padding="14,8"
                        BorderBrush="#334155" BorderThickness="1" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="Cong may in:" FontSize="13" Foreground="#94A3B8" Margin="0,0,8,0" VerticalAlignment="Center"/>
                        <TextBlock Name="TxtPrinterPort" Text="Dang quet..." FontSize="13" FontWeight="Bold"
                                   Foreground="#FBBF24" VerticalAlignment="Center"/>
                    </StackPanel>
                </Border>
            </Grid>
        </Border>

        <!-- Scrollable Cards Area -->
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" PanningMode="Both" Margin="0,0,0,14">
            <StackPanel Margin="0,0,10,0">
                
                <!-- Section 1: Receipt Printers -->
                <Grid Margin="4,0,4,8">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Text="1. MAY IN HOA DON (80MM - HANG DOI XP-80C)"
                               FontSize="14" FontWeight="Bold" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="1" Text="* Cham de chon 1 may in" FontSize="12" Foreground="#94A3B8" VerticalAlignment="Center"/>
                </Grid>
                
                <UniformGrid Name="PanelPrinters" Columns="2" Margin="0,0,0,16"/>

                <!-- Section 2: Other Devices -->
                <Grid Margin="4,10,4,8">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Text="2. THIET BI NGOAI VI &amp; MAY QUET"
                               FontSize="14" FontWeight="Bold" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="1" Text="* Cham de bat / tat thiet bi" FontSize="12" Foreground="#94A3B8" VerticalAlignment="Center"/>
                </Grid>

                <UniformGrid Name="PanelDevices" Columns="2" Margin="0,0,0,10"/>

            </StackPanel>
        </ScrollViewer>

        <!-- Progress and Terminal Output -->
        <Border Grid.Row="2" Background="#020617" CornerRadius="12" Padding="14" Margin="0,0,0,16"
                BorderBrush="#1E293B" BorderThickness="1.5">
            <StackPanel>
                <Grid Margin="0,0,0,8">
                    <TextBlock Name="TxtProgressStatus" Text="Nhat ky cai dat &amp; Trang thai"
                               FontSize="13" FontWeight="SemiBold" Foreground="#94A3B8" VerticalAlignment="Center"/>
                    <ProgressBar Name="ProgBar" Height="6" Width="220" HorizontalAlignment="Right"
                                 IsIndeterminate="False" Visibility="Collapsed" Foreground="#38BDF8"/>
                </Grid>
                <TextBox Name="TxtLog" Height="120" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                         Background="#020617" Foreground="#CBD5E1" FontFamily="Consolas" FontSize="12"
                         BorderThickness="0" TextWrapping="Wrap"/>
            </StackPanel>
        </Border>

        <!-- Bottom Action Buttons -->
        <Grid Grid.Row="3">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <Button Name="BtnRescan" Content="Quet lai USB" Height="58" Padding="20,0"
                    Background="#1E293B" Foreground="#F8FAFC" FontWeight="SemiBold" FontSize="14"
                    BorderBrush="#334155" BorderThickness="1.5" Cursor="Hand">
                <Button.Resources>
                    <Style TargetType="Border">
                        <Setter Property="CornerRadius" Value="12"/>
                    </Style>
                </Button.Resources>
            </Button>

            <Button Grid.Column="2" Name="BtnInstall" Content="CAI DAT THIET BI DA CHON"
                    Height="58" Padding="32,0" Margin="0,0,12,0"
                    Background="#2563EB" Foreground="#FFFFFF" FontWeight="Bold" FontSize="15"
                    BorderThickness="0" Cursor="Hand">
                <Button.Resources>
                    <Style TargetType="Border">
                        <Setter Property="CornerRadius" Value="12"/>
                    </Style>
                </Button.Resources>
            </Button>

            <Button Grid.Column="3" Name="BtnClose" Content="Dong" Height="58" Padding="28,0"
                    Background="#334155" Foreground="#F8FAFC" FontWeight="SemiBold" FontSize="15"
                    BorderThickness="0" Cursor="Hand">
                <Button.Resources>
                    <Style TargetType="Border">
                        <Setter Property="CornerRadius" Value="12"/>
                    </Style>
                </Button.Resources>
            </Button>
        </Grid>

    </Grid>
</Window>
"@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Get UI Elements
$panelPrinters = $window.FindName('PanelPrinters')
$panelDevices = $window.FindName('PanelDevices')
$txtPrinterPort = $window.FindName('TxtPrinterPort')
$txtProgressStatus = $window.FindName('TxtProgressStatus')
$progBar = $window.FindName('ProgBar')
$txtLog = $window.FindName('TxtLog')
$btnRescan = $window.FindName('BtnRescan')
$btnInstall = $window.FindName('BtnInstall')
$btnClose = $window.FindName('BtnClose')

# Brushes
$brushBgNormal    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
$brushBgSelected  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3A8A")
$brushBorderNorm  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#334155")
$brushBorderSel   = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
$brushTextWhite   = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8FAFC")
$brushTextMuted   = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
$brushGreenBadge  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#064E3B")
$brushGreenText   = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
$brushAccent      = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
$brushIndicatorBg = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")
$brushIndicatorBd = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#475569")
$brushSuccess     = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#059669")

$script:printerCards = @()
$script:deviceCards  = @()

function Create-Card {
    param(
        [string] $Id,
        [string] $Name,
        [string] $Subtitle,
        [string] $IconText,
        [bool] $IsRadio,
        [bool] $IsDetected,
        [bool] $IsChecked
    )

    $card = New-Object System.Windows.Controls.Border
    $card.MinHeight = 82
    $card.CornerRadius = New-Object System.Windows.CornerRadius(12)
    $card.BorderThickness = New-Object System.Windows.Thickness(2)
    $card.Margin = New-Object System.Windows.Thickness(4, 4, 4, 4)
    $card.Padding = New-Object System.Windows.Thickness(14, 12, 14, 12)
    $card.Cursor = [System.Windows.Input.Cursors]::Hand

    $card.Tag = [PSCustomObject] @{
        Id = $Id
        Name = $Name
        IsRadio = $IsRadio
        IsDetected = $IsDetected
        IsChecked = $IsChecked
        IndicatorBox = $null
        Dot = $null
        Check = $null
    }

    $grid = New-Object System.Windows.Controls.Grid
    $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = [System.Windows.GridLength]::Auto
    $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = [System.Windows.GridLength]::Auto
    $null = $grid.ColumnDefinitions.Add($col0)
    $null = $grid.ColumnDefinitions.Add($col1)
    $null = $grid.ColumnDefinitions.Add($col2)

    # Icon
    $iconBorder = New-Object System.Windows.Controls.Border
    $iconBorder.Width = 42
    $iconBorder.Height = 42
    $iconBorder.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $iconBorder.Background = $brushIndicatorBg
    $iconBorder.BorderBrush = $brushBorderNorm
    $iconBorder.BorderThickness = New-Object System.Windows.Thickness(1)
    $iconBorder.Margin = New-Object System.Windows.Thickness(0, 0, 14, 0)
    $iconBorder.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $iconBlock = New-Object System.Windows.Controls.TextBlock
    $iconBlock.Text = $IconText
    $iconBlock.FontSize = 12
    $iconBlock.FontWeight = [System.Windows.FontWeights]::Bold
    $iconBlock.Foreground = $brushAccent
    $iconBlock.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $iconBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $iconBorder.Child = $iconBlock
    [System.Windows.Controls.Grid]::SetColumn($iconBorder, 0)
    $null = $grid.Children.Add($iconBorder)

    # Info Stack
    $infoStack = New-Object System.Windows.Controls.StackPanel
    $infoStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text = $Name
    $titleBlock.FontSize = 15
    $titleBlock.FontWeight = [System.Windows.FontWeights]::Bold
    $titleBlock.Foreground = $brushTextWhite
    $titleBlock.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $null = $infoStack.Children.Add($titleBlock)

    $subBlock = New-Object System.Windows.Controls.TextBlock
    $subBlock.Text = $Subtitle
    $subBlock.FontSize = 12
    $subBlock.Foreground = $brushTextMuted
    $subBlock.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    $subBlock.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $null = $infoStack.Children.Add($subBlock)

    if ($IsDetected) {
        $badge = New-Object System.Windows.Controls.Border
        $badge.Background = $brushGreenBadge
        $badge.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $badge.Padding = New-Object System.Windows.Thickness(8, 2, 8, 2)
        $badge.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
        $badge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left

        $badgeText = New-Object System.Windows.Controls.TextBlock
        $badgeText.Text = "DA CAM USB"
        $badgeText.FontSize = 10
        $badgeText.FontWeight = [System.Windows.FontWeights]::Bold
        $badgeText.Foreground = $brushGreenText
        $badge.Child = $badgeText

        $null = $infoStack.Children.Add($badge)
    }

    [System.Windows.Controls.Grid]::SetColumn($infoStack, 1)
    $null = $grid.Children.Add($infoStack)

    # Indicator
    $indicatorBox = New-Object System.Windows.Controls.Border
    $indicatorBox.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $indicatorBox.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)

    if ($IsRadio) {
        $indicatorBox.Width = 26
        $indicatorBox.Height = 26
        $indicatorBox.CornerRadius = New-Object System.Windows.CornerRadius(13)
        $indicatorBox.BorderThickness = New-Object System.Windows.Thickness(2)

        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 12
        $dot.Height = 12
        $dot.Fill = $brushAccent
        $indicatorBox.Child = $dot
        $card.Tag.Dot = $dot
    } else {
        $indicatorBox.Width = 28
        $indicatorBox.Height = 28
        $indicatorBox.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $indicatorBox.BorderThickness = New-Object System.Windows.Thickness(2)

        $check = New-Object System.Windows.Controls.TextBlock
        $check.Text = [char]0x2713
        $check.FontWeight = [System.Windows.FontWeights]::Bold
        $check.FontSize = 15
        $check.Foreground = [System.Windows.Media.Brushes]::White
        $check.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $check.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $indicatorBox.Child = $check
        $card.Tag.Check = $check
    }
    $card.Tag.IndicatorBox = $indicatorBox

    [System.Windows.Controls.Grid]::SetColumn($indicatorBox, 2)
    $null = $grid.Children.Add($indicatorBox)

    $card.Child = $grid

    Update-CardVisual $card

    # Touch / Mouse click event
    $card.Add_MouseDown({
        param($sender, $e)
        if ($sender.Tag.IsRadio) {
            # Deselect all radio cards
            foreach ($rc in $script:printerCards) {
                $rc.Tag.IsChecked = ($rc -eq $sender)
                Update-CardVisual $rc
            }
        } else {
            # Toggle checkbox card
            $sender.Tag.IsChecked = -not $sender.Tag.IsChecked
            Update-CardVisual $sender
        }
        Update-InstallButtonText
    })

    return $card
}

function Update-InstallButtonText {
    $count = 0
    $chosenPrinter = $script:printerCards | Where-Object { $_.Tag.IsChecked -and $_.Tag.Id } | Select-Object -First 1
    if ($chosenPrinter) { $count++ }
    $chosenDevices = $script:deviceCards | Where-Object { $_.Tag.IsChecked }
    $count += $chosenDevices.Count
    if ($count -gt 0) {
        $btnInstall.Content = "CAI DAT THIET BI DA CHON ($count)"
    } else {
        $btnInstall.Content = "CAI DAT THIET BI DA CHON"
    }
}

function Update-CardVisual($card) {
    $tag = $card.Tag
    if ($tag.IsChecked) {
        $card.Background = $brushBgSelected
        $card.BorderBrush = $brushBorderSel
        if ($tag.IsRadio) {
            $tag.IndicatorBox.BorderBrush = $brushBorderSel
            $tag.IndicatorBox.Background = $brushIndicatorBg
            $tag.Dot.Visibility = [System.Windows.Visibility]::Visible
        } else {
            $tag.IndicatorBox.BorderBrush = $brushBorderSel
            $tag.IndicatorBox.Background = $brushAccent
            $tag.Check.Visibility = [System.Windows.Visibility]::Visible
        }
    } else {
        $card.Background = $brushBgNormal
        $card.BorderBrush = $brushBorderNorm
        if ($tag.IsRadio) {
            $tag.IndicatorBox.BorderBrush = $brushIndicatorBd
            $tag.IndicatorBox.Background = $brushIndicatorBg
            $tag.Dot.Visibility = [System.Windows.Visibility]::Collapsed
        } else {
            $tag.IndicatorBox.BorderBrush = $brushIndicatorBd
            $tag.IndicatorBox.Background = $brushIndicatorBg
            $tag.Check.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }
}

function Refresh-DevicesUI {
    $detectedIds = Get-DetectedDevices
    $usbPrinterPort = @(Get-ConnectedUsbPrinterPort) | Select-Object -First 1

    if ($usbPrinterPort) {
        $txtPrinterPort.Text = $usbPrinterPort
        $txtPrinterPort.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
    } else {
        $txtPrinterPort.Text = "Chua thay"
        $txtPrinterPort.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24")
    }

    $detectedPrinter = $detectedIds | Where-Object {
        $id = $_
        ($devices | Where-Object { $_.id -eq $id -and $_.group -eq 'printer' })
    } | Select-Object -First 1

    # Populate Printers
    $panelPrinters.Children.Clear()
    $script:printerCards = @()

    $printerEntries = @(
        [pscustomobject] @{ id = ''; name = 'Khong dung may in bill'; sub = 'Bo qua cai dat may in hoa don'; icon = 'NONE' }
    )
    foreach ($p in ($devices | Where-Object { $_.group -eq 'printer' })) {
        $icon = 'BILL'
        $sub = "Kho 80mm - Hang doi: $PosQueueName"
        if ($p.id -eq 'xprinter-q260') { $sub = "May in bill pho bien nhat GoodM - Hang doi: $PosQueueName" }
        $printerEntries += [pscustomobject] @{ id = $p.id; name = $p.name; sub = $sub; icon = $icon }
    }

    foreach ($entry in $printerEntries) {
        $isDet = ($entry.id -and ($detectedIds -contains $entry.id))
        $isChk = $false
        if ($detectedPrinter) {
            $isChk = ($entry.id -eq $detectedPrinter)
        } else {
            $isChk = ($entry.id -eq '')
        }

        $c = Create-Card -Id $entry.id -Name $entry.name -Subtitle $entry.sub -IconText $entry.icon -IsRadio $true -IsDetected $isDet -IsChecked $isChk
        $null = $panelPrinters.Children.Add($c)
        $script:printerCards += $c
    }

    # Populate Other Devices
    $panelDevices.Children.Clear()
    $script:deviceCards = @()

    foreach ($d in ($devices | Where-Object { $_.group -ne 'printer' })) {
        $icon = 'DEV'
        $sub = 'Thiet bi ngoai vi ket noi USB'
        if ($d.id -match 'hanel') { $icon = 'CCCD'; $sub = 'Dau doc the CCCD gan chip' }
        elseif ($d.id -match 'barcode') { $icon = 'SCAN'; $sub = 'May quet ma vach 1D / 2D / QR Code' }
        elseif ($d.id -match 'brother-hl') { $icon = 'A4'; $sub = 'May in van phong kho A4' }
        elseif ($d.id -match 'ricoh|brother|avision') { $icon = 'DOC'; $sub = 'May scan tai lieu toc do cao' }

        $isDet = ($detectedIds -contains $d.id)
        $isChk = $isDet

        $c = Create-Card -Id $d.id -Name $d.name -Subtitle $sub -IconText $icon -IsRadio $false -IsDetected $isDet -IsChecked $isChk
        $null = $panelDevices.Children.Add($c)
        $script:deviceCards += $c
    }

    Update-InstallButtonText
}

# Initial UI population
Refresh-DevicesUI

# Rescan button
$btnRescan.Add_Click({
    $txtProgressStatus.Text = "Dang quet lai thiet bi USB..."
    Refresh-DevicesUI
    $txtProgressStatus.Text = "Da cap nhat danh sach thiet bi theo cong USB."
})

# Close button
$btnClose.Add_Click({
    $window.Close()
})

# Install button
$btnInstall.Add_Click({
    if ($script:isInstalledSuccessfully) {
        $window.Close()
        return
    }

    $chosenPrinter = $script:printerCards | Where-Object { $_.Tag.IsChecked -and $_.Tag.Id } | Select-Object -First 1
    $chosenDevices = $script:deviceCards  | Where-Object { $_.Tag.IsChecked }

    $ids = @()
    if ($chosenPrinter) { $ids += $chosenPrinter.Tag.Id }
    if ($chosenDevices) { $ids += ($chosenDevices | ForEach-Object { $_.Tag.Id }) }

    if (-not $ids) {
        $txtLog.AppendText("Chua chon thiet bi nao de cai dat.`r`n")
        $txtProgressStatus.Text = "Chua co thiet bi nao duoc chon."
        return
    }

    # Disable buttons during install
    $btnInstall.IsEnabled = $false
    $btnRescan.IsEnabled  = $false
    $btnClose.IsEnabled   = $false
    $progBar.Visibility   = [System.Windows.Visibility]::Visible
    $progBar.IsIndeterminate = $true

    $txtProgressStatus.Text = "Dang tien hanh cai dat $( $ids.Count ) thiet bi..."
    $txtLog.AppendText("Bat dau cai dat: $( $ids -join ', ' )`r`n`r`n")

    $write = {
        param($text)
        $txtLog.AppendText("$text`r`n")
        $txtLog.ScrollToEnd()
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
            [Action]{}, [System.Windows.Threading.DispatcherPriority]::Background
        )
        Add-Content -LiteralPath $logFile -Value $text
    }

    $failed = Install-Devices $ids $write

    $progBar.IsIndeterminate = $false
    $progBar.Visibility = [System.Windows.Visibility]::Collapsed
    $btnClose.IsEnabled = $true

    if ($failed) {
        $script:isInstalledSuccessfully = $false
        $txtProgressStatus.Text = "Cai dat co loi o mot so thiet bi. Xem nhat ky ben duoi."
        $txtProgressStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
        $btnInstall.Content = "CO LOI - BAM DE THU LAI"
        $btnInstall.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626")
        $btnInstall.IsEnabled = $true
        $btnRescan.IsEnabled = $true
    } else {
        $script:isInstalledSuccessfully = $true
        $txtProgressStatus.Text = "Toan bo thiet bi da duoc cai dat thanh cong!"
        $txtProgressStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        $btnInstall.Content = "DA HOAN TAT - BAM DE DONG"
        $btnInstall.Background = $brushSuccess
        $btnInstall.IsEnabled = $true
    }
})

# Show the modern touch-friendly dialog
[void] $window.ShowDialog()
