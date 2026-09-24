# Shared helpers for peripherals\<device>\install.ps1 (dot-sourced by Peripherals.ps1).

# Every receipt printer is published under this queue name and made the default printer,
# so the POS software never needs reconfiguring when the printer brand changes.
$PosQueueName = 'XP-80C'

function Get-ConnectedUsbPrinterPort {
    # usbmon ports of USB printers that are plugged in right now (Linked = 1), e.g. USB001.
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses\{28d78fad-5a12-11d1-ae5b-0000f803a8c2}'
    foreach ($device in Get-ChildItem -LiteralPath $classKey -ErrorAction 'SilentlyContinue') {
        $linked = (Get-ItemProperty -LiteralPath (Join-Path $device.PSPath '#\Control') -ErrorAction 'SilentlyContinue').Linked
        $parameters = Get-ItemProperty -LiteralPath (Join-Path $device.PSPath '#\Device Parameters') -ErrorAction 'SilentlyContinue'
        if ($linked -eq 1 -and $parameters.'Port Number') {
            '{0}{1:D3}' -f $parameters.'Base Name', $parameters.'Port Number'
        }
    }
}

function Install-PosPrinterDriver([string] $InfPath, [string] $DriverName) {
    if (-not (Test-Path -LiteralPath $InfPath)) { throw "Driver not found: $InfPath" }
    # These printer drivers are Authenticode-signed (not WHQL): trust the signing publisher first,
    # as the vendors' own installers do, otherwise pnputil refuses the package silently.
    foreach ($catalog in Get-ChildItem -LiteralPath (Split-Path -Parent $InfPath) -Filter '*.cat') {
        $signature = Get-AuthenticodeSignature -LiteralPath $catalog.FullName
        if ($signature.Status -ne 'Valid') { throw "$($catalog.Name): signature $($signature.Status)" }
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPublisher', 'LocalMachine')
        $store.Open('ReadWrite'); $store.Add($signature.SignerCertificate); $store.Close()
    }
    pnputil.exe /add-driver "$InfPath" /install | Where-Object { $_ -match '\S' }
    if (-not (Get-PrinterDriver -Name $DriverName -ErrorAction 'SilentlyContinue')) {
        Add-PrinterDriver -Name $DriverName
    }
}

function Set-PosPrinter([string] $DriverName, [string] $PortName = '') {
    if (-not $PortName) {
        $PortName = @(Get-ConnectedUsbPrinterPort) | Select-Object -First 1
        if (-not $PortName) { throw 'Khong thay may in USB nao dang cam - cam may in, bat nguon roi chay lai.' }
    }
    if (-not (Get-PrinterPort -Name $PortName -ErrorAction 'SilentlyContinue')) { Add-PrinterPort -Name $PortName }
    Get-Printer -Name $PosQueueName -ErrorAction 'SilentlyContinue' | Remove-Printer
    Add-Printer -Name $PosQueueName -DriverName $DriverName -PortName $PortName
    Set-PosDefaultPrinter
    "May in '$PosQueueName' -> $DriverName tren cong $PortName (mac dinh)"
}

function Set-PosDefaultPrinter {
    # Stop Windows from moving the default printer around, then make the POS queue the default.
    Set-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -Name 'LegacyDefaultPrinterMode' -Type DWord -Value 1
    $printer = Get-CimInstance -ClassName 'Win32_Printer' -Filter "Name = '$PosQueueName'"
    if ($printer) { $null = Invoke-CimMethod -InputObject $printer -MethodName 'SetDefaultPrinter' }
}

function Invoke-Installer([string] $Dir, [string] $Pattern, [string[]] $Arguments = @()) {
    # Runs the newest file matching $Pattern in $Dir; without $Arguments the vendor's own wizard is shown.
    $setup = Get-ChildItem -LiteralPath $Dir -Filter $Pattern -File -ErrorAction 'SilentlyContinue' |
        Sort-Object -Property 'Name' -Descending | Select-Object -First 1
    if (-not $setup) { throw "Chua co bo cai ($Pattern) trong $Dir - xem README.md trong thu muc do." }
    $startArgs = @{ FilePath = $setup.FullName; WorkingDirectory = $Dir; PassThru = $true }
    if ($Arguments) { $startArgs.ArgumentList = $Arguments }
    # Not Start-Process -Wait: it also waits for every process the installer leaves running
    # (e.g. Avision's SAC.exe agent) and would never return. Wait for the installer itself, then
    # for setup-like processes it spawned (wizards that hand over to a second setup/ISBEW), max 30 min.
    $started = Get-Date
    $process = Start-Process @startArgs
    $null = $process.Handle   # keeps ExitCode readable after exit (PowerShell 5.1)
    $process.WaitForExit()
    $deadline = (Get-Date).AddMinutes(30)
    while ((Get-Date) -lt $deadline -and (Get-Process -ErrorAction 'SilentlyContinue' | Where-Object {
        $_.StartTime -gt $started -and $_.ProcessName -match '(?i)setup|install|isbew|^_is|^is-'
    })) { Start-Sleep -Seconds 3 }
    if ($process.ExitCode -notin 0, 3010) { throw "$($setup.Name) exit code $($process.ExitCode)" }
    "$($setup.Name) xong (exit $($process.ExitCode))"
}
