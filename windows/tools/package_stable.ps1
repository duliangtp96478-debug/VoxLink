param([Parameter(Mandatory=$true)][string]$ReleaseDir,[Parameter(Mandatory=$true)][string]$ProjectRoot,[switch]$ExportExisting)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($false)
$goodHash='7EB4ABBD81F5FF2AB2019DE2616166CB4C707F09E66C67020CDC425570EF8665'
$originalHash='53238C00BED3FB6E0D822EB18F18DCAC093BB30D4502DBFE78B9057690B18699'
foreach($name in @('VoxLink.exe','VoxLinkCore.exe','flutter_windows.dll','data')) {if (!(Test-Path -LiteralPath (Join-Path $ReleaseDir $name))) {throw "Missing runtime item: $name"}}
$engine=Join-Path $ReleaseDir 'flutter_windows.dll'
$current=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
if($ExportExisting) {
 if($current -ne $goodHash){throw 'Source folder must contain the tested Fix7 engine. Apply Fix7 first.'}
} else {
 if($current -ne $originalHash){throw 'Generated engine does not match Flutter 3.47.6. Refusing to mix different engine versions.'}
}
$out=Join-Path $ProjectRoot 'Release\VoxLink_Stable_Portable'
if([IO.Path]::GetFullPath($ReleaseDir).TrimEnd('\') -eq [IO.Path]::GetFullPath($out).TrimEnd('\')){throw 'Source and destination must differ.'}
if(Test-Path -LiteralPath $out){throw 'Stable output already exists. Rename it before building again; existing files were not deleted.'}
$stage=Join-Path $ProjectRoot ('Release\_stable_stage_'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
 foreach($name in @('VoxLink.exe','VoxLinkCore.exe')){Copy-Item -LiteralPath (Join-Path $ReleaseDir $name) -Destination $stage}
 # Include all generated plugin/runtime DLLs; omit only known patch payload/backups.
 Get-ChildItem -LiteralPath $ReleaseDir -File -Filter '*.dll' | Where-Object {$_.Name -notmatch '^flutter_windows\.fix7'} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $stage}
 Copy-Item -LiteralPath (Join-Path $ReleaseDir 'data') -Destination $stage -Recurse
 if(!$ExportExisting){Copy-Item -LiteralPath (Join-Path $ProjectRoot 'engine\flutter_windows.dll') -Destination (Join-Path $stage 'flutter_windows.dll') -Force}
 if((Get-FileHash -LiteralPath (Join-Path $stage 'flutter_windows.dll') -Algorithm SHA256).Hash -ne $goodHash){throw 'Integrated repair hash mismatch.'}
 # Bundle the x64 MSVC runtime to avoid requiring a compiler or separate VC installer.
 $crtRoots=@()
 if($env:VCToolsRedistDir){$crtRoots+=Get-ChildItem -LiteralPath (Join-Path $env:VCToolsRedistDir 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue | ForEach-Object {$_.FullName}}
 if($env:VSROOT){$crtRoots+=Get-ChildItem -Path (Join-Path $env:VSROOT 'VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT') -Directory -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | ForEach-Object {$_.FullName}}
 foreach($name in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')) {
  $destination=Join-Path $stage $name
  if(!(Test-Path -LiteralPath $destination)) {
   $found=$null
   foreach($crt in $crtRoots){$candidate=Join-Path $crt $name;if(Test-Path -LiteralPath $candidate){$found=$candidate;break}}
   if(!$found -and $ExportExisting){$candidate=Join-Path $env:WINDIR ('System32\'+$name);if(Test-Path -LiteralPath $candidate){$found=$candidate}}
   if(!$found){throw "Cannot locate x64 MSVC runtime $name; no incomplete Stable package was published."}
   Copy-Item -LiteralPath $found -Destination $destination
  }
 }
 # Distribution notices and build records belong outside the runtime folder.
 $info=Join-Path $ProjectRoot 'Release\BuildInfo';New-Item -ItemType Directory -Path $info -Force | Out-Null
 Get-ChildItem -LiteralPath $stage -File | Get-FileHash -Algorithm SHA256 | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $info 'stable_hashes.json') -Encoding UTF8
 Copy-Item -LiteralPath (Join-Path $ProjectRoot 'licenses\LICENSE.windows_flutter.md') -Destination $info
 Move-Item -LiteralPath $stage -Destination $out
 Compress-Archive -LiteralPath $out,(Join-Path $info 'LICENSE.windows_flutter.md') -DestinationPath (Join-Path $ProjectRoot 'Release\VoxLink_Stable_Portable.zip') -Force
 Write-Host "[SUCCESS] $out"
 Write-Host ('Runtime top-level items: '+@(Get-ChildItem -LiteralPath $out).Count)
} finally {if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}}
