# Avision AV332U: TWAIN driver from avision.com. The Avision wizard is shown.
param([string] $Dir)
Invoke-Installer -Dir $Dir -Pattern '*.exe'
