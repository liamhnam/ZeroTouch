# Ricoh fi-800R: PaperStream IP (TWAIN) from pfu.ricoh.com (PSIPTWAIN-*.exe). The PFU wizard is shown.
param([string] $Dir)
Invoke-Installer -Dir $Dir -Pattern 'PSIPTWAIN*.exe'
