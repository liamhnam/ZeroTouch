# Runs elevated as the new local account at its first logon.

# --- Keep logging on automatically forever (blank password) ---
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -LiteralPath $winlogon -Name 'AutoAdminLogon' -Type String -Value '1'
Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultUserName' -Type String -Value $env:USERNAME
Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultDomainName' -Type String -Value $env:COMPUTERNAME
Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultPassword' -Type String -Value ''
Remove-ItemProperty -LiteralPath $winlogon -Name 'AutoLogonCount' -ErrorAction 'SilentlyContinue'

# --- Firewall once more, now that the service is fully up ---
netsh.exe advfirewall set allprofiles state off

# --- The internal disk must boot before the USB drive from now on ---
bcdedit.exe /set '{fwbootmgr}' displayorder '{bootmgr}' /addfirst

# --- Hand over to the USB payload: drivers, Wi-Fi, apps, inventory, final reboot ---
$payload = Get-PSDrive -PSProvider 'FileSystem' |
    ForEach-Object { Join-Path $_.Root 'AutoInstaller\postinstall.ps1' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if ($payload) {
    Start-Process -FilePath 'powershell.exe' -Wait `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$payload`"")
} else {
    $note = 'ZeroTouch: khong tim thay USB (\AutoInstaller\postinstall.ps1) - chua cai driver, Wi-Fi, phan mem.'
    Set-Content -LiteralPath 'C:\Users\Public\Desktop\LOI.txt' -Value $note -Encoding 'UTF8'
}
