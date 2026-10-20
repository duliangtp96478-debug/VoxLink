$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
try {
 $source=(Read-Host 'Paste the full folder path of your working Fix6 A + Fix7 Portable').Trim().Trim('"')
 if(!(Test-Path -LiteralPath $source -PathType Container)){throw 'Folder not found.'}
 & (Join-Path $PSScriptRoot 'package_stable.ps1') -ReleaseDir $source -ProjectRoot $root -ExportExisting
} catch {Write-Host ('[FAILED] '+$_.Exception.Message) -ForegroundColor Red;exit 1}
