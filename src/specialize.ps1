# Runs as SYSTEM during the specialize pass, before any user account exists.
# Defender services are already disabled offline by pe.cmd; this script handles the rest.

# --- Firewall: off for every profile (policy + live state) ---
foreach ($firewallProfile in 'DomainProfile', 'StandardProfile', 'PublicProfile') {
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\$firewallProfile" /v EnableFirewall /t REG_DWORD /d 0 /f
}
netsh.exe advfirewall set allprofiles state off

# --- Windows Update: no automatic updates, never pull drivers from Windows Update ---
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ExcludeWUDriversInQualityUpdate /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" /v DontSearchWindowsUpdate /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" /v SearchOrderConfig /t REG_DWORD /d 0 /f
# WaaSMedicSvc would otherwise re-enable wuauserv (seen in testing)
foreach ($service in 'wuauserv', 'UsoSvc', 'WaaSMedicSvc') {
    reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\$service" /v Start /t REG_DWORD /d 4 /f
}

# --- Defender: policy as a second layer on top of the disabled services ---
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f

# --- Power: best available performance plan, never sleep, never turn the display off ---
$ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$highPerformance = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$zeroTouchPlan = '2d4f9c1e-6a7b-4e3c-9f10-5a1b2c3d4e5f'
powercfg.exe /duplicatescheme $ultimate $zeroTouchPlan
if ($LASTEXITCODE -eq 0) {
    powercfg.exe /changename $zeroTouchPlan 'ZeroTouch Performance'
    powercfg.exe /setactive $zeroTouchPlan
} else {
    powercfg.exe /setactive $highPerformance
}
foreach ($setting in 'monitor-timeout', 'standby-timeout', 'hibernate-timeout', 'disk-timeout') {
    powercfg.exe /change "$setting-ac" 0
    powercfg.exe /change "$setting-dc" 0
}
powercfg.exe /hibernate off
# USB selective suspend off (keeps the USB Wi-Fi adapter awake)
powercfg.exe /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg.exe /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
# PCI Express link state power management off
powercfg.exe /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0
# Wireless adapter: maximum performance
powercfg.exe /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0
powercfg.exe /setactive SCHEME_CURRENT
