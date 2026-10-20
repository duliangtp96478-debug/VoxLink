@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
title VoxLink V1.0 Build
cd /d "%~dp0"
set "AROOT=%CD%"
set "ROOT=%AROOT%\.."
set "WORK=%AROOT%\_flutter_build"
set "APK=%ROOT%\Release\VoxLink_Android_AEC_Test1.apk"

echo ============================================================
echo   VoxLink Final V1.0 - Android APK Build
echo   Flutter UI + Kotlin AudioRecord Foreground Service
echo ============================================================
echo.

where flutter >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Cannot locate Flutter. Check the preceding output.
  pause
  exit /b 1
)

echo [1/5] Generate Flutter Android project...
if exist "%WORK%" rmdir /s /q "%WORK%"
call flutter create --platforms=android --org com.voxlink --project-name app "%WORK%"
if errorlevel 1 goto :fail

echo [2/5] Install Flutter and Kotlin sources...
copy /Y "%AROOT%\flutter_seed\pubspec.yaml" "%WORK%\pubspec.yaml" >nul
copy /Y "%AROOT%\flutter_seed\lib\main.dart" "%WORK%\lib\main.dart" >nul
copy /Y "%AROOT%\native\AndroidManifest.xml" "%WORK%\android\app\src\main\AndroidManifest.xml" >nul
set "KDIR=%WORK%\android\app\src\main\kotlin\com\voxlink\app"
if not exist "%KDIR%" mkdir "%KDIR%"
copy /Y "%AROOT%\native\MainActivity.kt" "%KDIR%\MainActivity.kt" >nul
copy /Y "%AROOT%\native\VoxLinkService.kt" "%KDIR%\VoxLinkService.kt" >nul

echo [3/5] Install Android icons...
for %%D in (mipmap-mdpi mipmap-hdpi mipmap-xhdpi mipmap-xxhdpi mipmap-xxxhdpi) do (
  if not exist "%WORK%\android\app\src\main\res\%%D" mkdir "%WORK%\android\app\src\main\res\%%D"
  copy /Y "%ROOT%\resources\android\%%D\ic_launcher.png" "%WORK%\android\app\src\main\res\%%D\ic_launcher.png" >nul
)

echo [4/5] Resolve Flutter dependencies...
pushd "%WORK%"
call flutter pub get
if errorlevel 1 (
  popd
  goto :fail
)

echo [5/5] Build Android Release APK...
call flutter build apk --release
if errorlevel 1 (
  popd
  goto :fail
)
popd

if not exist "%WORK%\build\app\outputs\flutter-apk\app-release.apk" (
  echo [ERROR] Cannot locate app-release.apk. Check the preceding output.
  goto :fail
)

if not exist "%ROOT%\Release" mkdir "%ROOT%\Release"
copy /Y "%WORK%\build\app\outputs\flutter-apk\app-release.apk" "%APK%" >nul
copy /Y "%ROOT%\resources\android\playstore\icon_512.png" "%ROOT%\Release\VoxLink_icon_512.png" >nul

echo.
echo ============================================================
echo [SUCCESS] Build completed.
echo Output: %APK%
echo ============================================================
pause
exit /b 0

:fail
echo.
echo ============================================================
echo [FAILED] Build failed. Copy the last error lines for diagnosis.
echo Check the build output above for details.
echo ============================================================
pause
exit /b 1
