param(
  [Parameter(Mandatory=$true)][string]$ProjectDir,
  [Parameter(Mandatory=$true)][string]$IconPath
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$iconDst = Join-Path $ProjectDir 'windows\runner\resources\app_icon.ico'
Copy-Item -Force $IconPath $iconDst

$main = Join-Path $ProjectDir 'windows\runner\main.cpp'
if (Test-Path $main) {
  $s = [System.IO.File]::ReadAllText($main, $utf8)
  $s = [regex]::Replace($s, 'window\.Create\(L"[^"]+"', 'window.Create(L"VoxLink"', 1)

  # Stable diagnostic: override the default Flutter 3.47+ Windows Impeller renderer.
  # This is injected into the GENERATED runner after flutter create, so a rebuild
  # doesn't silently erase the test. No changes are made to audio or UI logic.
  $anchor = 'flutter::DartProject project(L"data");'
  if (-not $s.Contains($anchor)) {
    throw 'VoxLink Stable: generated Windows runner main.cpp lacks the expected Flutter DartProject anchor. No silent fallback.'
  }
  if (-not $s.Contains('project.set_impeller_switch(')) {
    $switch = '  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);'
    $s = $s.Replace($anchor, $anchor + [Environment]::NewLine + $switch)
  }
  [System.IO.File]::WriteAllText($main, $s, $utf8)
  Write-Host '[STABLE] Forced Flutter Windows renderer: Skia (Impeller disabled)' 
}

$cmake = Join-Path $ProjectDir 'windows\CMakeLists.txt'
if (Test-Path $cmake) {
  $s = [System.IO.File]::ReadAllText($cmake, $utf8)
  $s = [regex]::Replace($s, 'set\(BINARY_NAME\s+"[^"]+"\)', 'set(BINARY_NAME "VoxLink")', 1)
  [System.IO.File]::WriteAllText($cmake, $s, $utf8)
}
Write-Host '[OK] VoxLink Windows runner prepared.'
