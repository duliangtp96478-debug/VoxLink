@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"

where cmake >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Cannot locate CMake. Check the preceding output.
  exit /b 1
)

if exist build rmdir /s /q build
cmake -S . -B build -A x64
if errorlevel 1 exit /b 1
cmake --build build --config Release
if errorlevel 1 exit /b 1
copy /Y "build\Release\VoxLinkCore.exe" "..\VoxLinkCore.exe" >nul
if not exist "..\VoxLinkCore.exe" exit /b 1
echo [OK] Native Core built.
exit /b 0
