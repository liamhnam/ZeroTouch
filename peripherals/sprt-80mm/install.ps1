# SPRT 80 mm: SPRT driver 2.15.5 "80mm Series Printer" (POS88EN.inf, extracted from SP-DRV2155Win.exe).
param([string] $Dir, [string] $PortName = '')
Install-PosPrinterDriver -InfPath (Join-Path $Dir 'driver\POS88EN.inf') -DriverName '80mm Series Printer'
Set-PosPrinter -DriverName '80mm Series Printer' -PortName $PortName
