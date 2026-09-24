# Brother HL-L2361DN (A4 laser, USB/LAN): "Full Driver & Software Package" or "Printer Driver" from
# support.brother.com. The Brother wizard is shown; it keeps its own queue name (not the receipt queue).
param([string] $Dir)
Invoke-Installer -Dir $Dir -Pattern '*.exe'
