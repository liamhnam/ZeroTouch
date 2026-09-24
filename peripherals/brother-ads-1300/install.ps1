# Brother ADS-1300: "Full Driver & Software Package" from support.brother.com. The Brother wizard is shown.
param([string] $Dir)
Invoke-Installer -Dir $Dir -Pattern '*.exe'
