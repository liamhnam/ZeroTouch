# Xprinter Q260 (80 mm): Xprinter driver V8.2 "XP-80C" (UniDrv, extracted from XPrinter Driver Setup V8.2.exe).
param([string] $Dir, [string] $PortName = '')
Install-PosPrinterDriver -InfPath (Join-Path $Dir 'driver\XPDRVx64.INF') -DriverName 'XP-80C'
Set-PosPrinter -DriverName 'XP-80C' -PortName $PortName
