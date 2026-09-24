# Epson TM-T81: Epson Advanced Printer Driver (APD). The Epson wizard is shown (choose TM-T81, USB);
# the queue it creates is then renamed to the common POS queue name and made the default.
param([string] $Dir, [string] $PortName = '')
Invoke-Installer -Dir $Dir -Pattern '*.exe'
$epson = Get-Printer | Where-Object { $_.DriverName -like '*TM-T81*' -and $_.Name -ne $PosQueueName } | Select-Object -First 1
if (-not $epson) {
    if (Get-Printer -Name $PosQueueName -ErrorAction 'SilentlyContinue') { Set-PosDefaultPrinter; return "May in '$PosQueueName' da co san" }
    throw 'Khong thay may in Epson TM-T81 sau khi cai APD'
}
Get-Printer -Name $PosQueueName -ErrorAction 'SilentlyContinue' | Remove-Printer
Rename-Printer -Name $epson.Name -NewName $PosQueueName
Set-PosDefaultPrinter
"May in '$PosQueueName' -> $($epson.DriverName) tren cong $($epson.PortName) (mac dinh)"
