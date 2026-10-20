@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
title VoxLink 1.0.1 Stable Build
cd /d "%~dp0"
set "PCROOT=%CD%"
set "ROOT=%PCROOT%\.."
set "WORK=%PCROOT%\_flutter_build_stable"
set "ICON=%ROOT%\resources\app_icon.ico"

echo ============================================================
echo   VoxLink 1.0.1 Stable - Windows Release Build
echo   Flutter UI + C++20 Native Core + WASAPI
echo   NO PYTHON
echo ============================================================
echo.

where flutter >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Cannot locate Flutter. Check the preceding output.
  pause
  exit /b 1
)

if not exist "%ICON%" (
  echo [ERROR] Cannot locate required build file/tool. Check the preceding output.
  pause
  exit /b 1
)

if not exist "%ROOT%\Release\BuildInfo" mkdir "%ROOT%\Release\BuildInfo"
call flutter --version --machine > "%ROOT%\Release\BuildInfo\flutter_version.json"
if errorlevel 1 goto :fail
powershell -NoProfile -ExecutionPolicy Bypass -Command "$v=Get-Content -LiteralPath (Join-Path $env:ROOT 'Release\BuildInfo\flutter_version.json') -Raw | ConvertFrom-Json; if($v.frameworkVersion -ne '3.47.6' -or $v.engineContentHash -ne 'b8c8d3d8d5d0095127057f8a29ca8cc53da2167c'){Write-Host 'This Stable build is pinned to the validated Flutter 3.47.6 engine.';exit 1}"
if errorlevel 1 goto :fail
echo [0/6] Locate Visual Studio and CMake...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%VSWHERE%" (
  for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
)
if defined VSROOT (
  if exist "!VSROOT!\Common7\Tools\VsDevCmd.bat" call "!VSROOT!\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64 >nul
  if exist "!VSROOT!\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" set "PATH=!VSROOT!\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;!PATH!"
)

where cmake >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Cannot locate CMake. Check the preceding output.
  echo Check the build output above for details.
  pause
  exit /b 1
)

echo [1/6] Build C++ Native Core...

call "%PCROOT%\native_core\BUILD_NATIVE.cmd"
if errorlevel 1 goto :fail

echo [2/6] Generate Flutter Windows project...
if exist "%WORK%" rmdir /s /q "%WORK%"
call flutter config --enable-windows-desktop >nul 2>nul
call flutter create --platforms=windows --project-name voxlink "%WORK%"
if errorlevel 1 goto :fail

echo [3/6] Install UI and icon...
copy /Y "%PCROOT%\flutter_seed\pubspec.yaml" "%WORK%\pubspec.yaml" >nul
copy /Y "%PCROOT%\flutter_seed\pubspec.lock" "%WORK%\pubspec.lock" >nul
copy /Y "%PCROOT%\flutter_seed\lib\main.dart" "%WORK%\lib\main.dart" >nul
if not exist "%WORK%\assets" mkdir "%WORK%\assets"
copy /Y "%ICON%" "%WORK%\assets\app_icon.ico" >nul
if errorlevel 1 goto :fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%PCROOT%\tools\prepare_windows.ps1" -ProjectDir "%WORK%" -IconPath "%ICON%"
if errorlevel 1 goto :fail

echo [4/6] Resolve Flutter dependencies...
pushd "%WORK%"
call flutter pub get --enforce-lockfile
if errorlevel 1 (
  popd
  goto :fail
)

echo [5/6] Build Windows Release...
call flutter build windows --release
if errorlevel 1 (
  popd
  goto :fail
)
popd

set "REL=%WORK%\build\windows\x64\runner\Release"
if not exist "%REL%\VoxLink.exe" set "REL=%WORK%\build\windows\runner\Release"
if not exist "%REL%\VoxLink.exe" (
  echo [ERROR] Cannot locate Flutter. Check the preceding output.
  goto :fail
)

copy /Y "%PCROOT%\VoxLinkCore.exe" "%REL%\VoxLinkCore.exe" >nul
if not exist "%REL%\VoxLinkCore.exe" (
  echo [ERROR] Cannot locate VoxLinkCore.exe. Check the preceding output.
  goto :fail
)

echo [6/6] Integrate validated repair and package clean runtime...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PCROOT%\tools\package_stable.ps1" -ReleaseDir "%REL%" -ProjectRoot "%ROOT%"
if errorlevel 1 goto :fail
echo [SUCCESS] Release\VoxLink_Stable_Portable.zip
pause
exit /b 0
:fail
echo [FAILED] Build did not finish. Do not use partial output.
pause
exit /b 1
