<#
.SYNOPSIS
    Merge inventory.csv files from several ZeroTouch USB drives into one.

.EXAMPLE
    .\tools\merge-inventory.ps1 -Path E:\, F:\, .\old\inventory.csv -Output .\inventory-all.csv
#>
param(
    [Parameter(Mandatory)] [string[]] $Path,
    [string] $Output = 'inventory-all.csv'
)

$ErrorActionPreference = 'Stop'

$files = foreach ($item in $Path) {
    if (Test-Path -LiteralPath $item -PathType 'Leaf') {
        Get-Item -LiteralPath $item
    } else {
        Get-ChildItem -LiteralPath $item -Filter 'inventory.csv' -Recurse -ErrorAction 'SilentlyContinue'
    }
}
if (-not $files) { throw 'No inventory.csv found' }

$seen = @{}
$rows = foreach ($file in $files) {
    foreach ($row in Import-Csv -LiteralPath $file.FullName) {
        $key = "$($row.ComputerName)|$($row.FinishedAt)"
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $row
        }
    }
}
$rows | Sort-Object -Property 'FinishedAt' | Export-Csv -LiteralPath $Output -NoTypeInformation -Encoding 'UTF8'
Write-Host "Merged $(@($rows).Count) row(s) from $(@($files).Count) file(s) into $Output"
