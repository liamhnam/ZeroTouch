# Avision AV332U: TWAIN driver V6.21 (AV332U_V6.21.09112026.zip from avision.com, extracted to driver\).
# InstallShield setup with the recorded response file it ships (setup.iss) -> silent install.
param([string] $Dir)
$driver = Join-Path $Dir 'driver'
Invoke-Installer -Dir $driver -Pattern 'setup.exe' -Arguments '/s', "/f1`"$(Join-Path $driver 'setup.iss')`"", '/f2"C:\ZeroTouch\logs\avision-setup.log"'
