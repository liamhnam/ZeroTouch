# Hanel HN212 ID-card reader: .NET 6 Desktop Runtime + VC++ 2015-2022, app in Program Files, starts at logon.
param([string] $Dir)
Invoke-Installer -Dir $Dir -Pattern 'windowsdesktop-runtime-6.*-win-x64.exe' -Arguments '/install', '/quiet', '/norestart'
Invoke-Installer -Dir $Dir -Pattern 'vcredist2015_2017_2019_2022_x64.exe' -Arguments '/install', '/quiet', '/norestart'
Invoke-Installer -Dir $Dir -Pattern 'vcredist2015_2017_2019_2022_x86.exe' -Arguments '/install', '/quiet', '/norestart'

$target = Join-Path $env:ProgramFiles 'Hanel\ReadIdCard'
robocopy.exe (Join-Path $Dir 'ReadIdCard') $target /E /R:1 /W:1 /NFL /NDL /NJH /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Copy to $target failed (robocopy $LASTEXITCODE)" }

$exe = Join-Path $target 'IdCard.Hanel.exe'
$shell = New-Object -ComObject 'WScript.Shell'
foreach ($folder in [Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('CommonStartup')) {
    $link = $shell.CreateShortcut((Join-Path $folder 'Hanel HN212.lnk'))
    $link.TargetPath = $exe
    $link.WorkingDirectory = $target
    $link.Save()
}
if (-not (Get-Process -Name 'IdCard.Hanel' -ErrorAction 'SilentlyContinue')) { Start-Process -FilePath $exe -WorkingDirectory $target }
"Hanel HN212 -> $target (tu chay khi dang nhap)"
