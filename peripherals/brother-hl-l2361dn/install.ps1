# Brother HL-L2361DN (A4 laser): Brother "Printer Driver" 1.11.0.0 (Y14A_C1-hostm-1110.EXE from
# support.brother.com, extracted to driver\). The INF matches the USB printer (Brother HL-L2360D series),
# so Windows creates the queue by itself once the driver is in the store; it keeps its own name.
param([string] $Dir)
$inf = Join-Path $Dir 'driver\32_64\BROHL13A.INF'
if (-not (Test-Path -LiteralPath $inf)) { throw "Driver not found: $inf" }
pnputil.exe /add-driver "$inf" /install | Where-Object { $_ -match '\S' }
if (-not (Get-PrinterDriver -Name 'Brother HL-L2360D series' -ErrorAction 'SilentlyContinue')) {
    Add-PrinterDriver -Name 'Brother HL-L2360D series'
}
pnputil.exe /scan-devices | Out-Null
Start-Sleep -Seconds 5
$queue = Get-Printer | Where-Object { $_.DriverName -eq 'Brother HL-L2360D series' } | Select-Object -First 1
if ($queue) { "May in A4: '$($queue.Name)' tren cong $($queue.PortName)" } else { 'Driver da cai - cam cap USB may in, Windows se tu tao may in' }
