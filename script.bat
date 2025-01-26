@echo off
setlocal enabledelayedexpansion

REM Step 1: Check if ADB is installed
echo Checking if ADB is installed...
adb version >nul 2>&1
if errorlevel 1 (
    echo ERROR: ADB is not installed or not in PATH. Please install ADB and try again.
    pause
    exit /b 1
)
echo ADB is installed.

REM Step 2: Check if a device is connected
echo Checking if a device is connected...
set DEVICE_FOUND=false

for /f "skip=1 tokens=1,2" %%a in ('adb devices') do (
    if "%%b"=="device" (
        set DEVICE_FOUND=true
    )
)

if "%DEVICE_FOUND%"=="false" (
    echo ERROR: No device connected. Please connect a device and try again.
    pause
    exit /b 1
)
echo A device is connected.

REM Step 3: Get the DUAL_APP User ID
echo Retrieving user list...
set DUAL_APP_ID=

for /f "tokens=*" %%i in ('adb shell pm list users') do (
    echo %%i | findstr "DUAL_APP" >nul
    if not errorlevel 1 (
        for /f "tokens=2 delims={:}" %%j in ("%%i") do (
            set DUAL_APP_ID=%%j
        )
    )
)

if "%DUAL_APP_ID%"=="" (
    echo ERROR: DUAL_APP User not found.
    pause
    exit /b 1
)
echo DUAL_APP User found with ID: %DUAL_APP_ID%

REM Step 4: Prompt for Package Name
set /p PACKAGE_NAME=Enter the package name to clone: 

if "%PACKAGE_NAME%"=="" (
    echo ERROR: No package name provided.
    pause
    exit /b 1
)

REM Step 5: Check if the app exists
echo Checking if the app %PACKAGE_NAME% exists on the device...
for /f %%i in ('adb shell pm path %PACKAGE_NAME%') do (
    set APK_PATH=%%a
    set APK_PATH=!APK_PATH:package:=!
    set APP_PATHS=!APP_PATHS! %%i
)

REM Check if APP_PATHS is empty (no package found)
if "%APP_PATHS%"=="" (
    echo ERROR: The package "%PACKAGE_NAME%" does not exist on the device.
    pause
    exit /b 1
)

echo The package "%PACKAGE_NAME%" exists. Preparing to pull APK files...

REM Step 6: Create a folder for the package
if not exist "%PACKAGE_NAME%" mkdir "%PACKAGE_NAME%"
cd "%PACKAGE_NAME%"

REM Step 7: Pull all APK files
echo Pulling APK files...

for /f %%i in ('adb shell pm path %PACKAGE_NAME%') do (
    set APK_PATH=%%i
    set APK_PATH=!APK_PATH:package:=!
    adb pull !APK_PATH!
)

:: Initialize an empty string for the file list
set "filelist="

:: Loop through all the APK files in the directory and add them to the file list
for %%F in (*.apk) do (
    set "filelist=!filelist! "%%F""
)

REM Step 8: Install

:: Run the adb install-multiple command with the collected files
echo Installing %PACKAGE_NAME% for user %DUAL_APP_ID%
adb install-multiple --user %DUAL_APP_ID% !filelist!

REM Step 9: Copy Permissions

echo Cloning permissions for %PACKAGE_NAME%...
for /f "tokens=*" %%i in ('adb shell appops get %PACKAGE_NAME%') do (
    REM Parse the permission name and status
    for /f "tokens=1,2 delims=:" %%a in ("%%i") do (
        set PERMISSION=%%a
        set STATUS=%%b

        REM Remove leading/trailing spaces
        set PERMISSION=!PERMISSION: =!
        set STATUS=!STATUS: =!

        REM Remove everything after the first semicolon (if present)
        for /f "tokens=1 delims=;" %%c in ("!STATUS!") do (
            set STATUS=%%c
        )

        REM Output the result
        adb shell appops set --user %DUAL_APP_ID% %PACKAGE_NAME% !PERMISSION! !STATUS!
    )
)
echo %PACKAGE_NAME% installed for USER %DUAL_APP_ID%.

REM Step 10: Clear up & Finish
cd ..
RMDIR /S /Q %PACKAGE_NAME%
echo Press any key to exit...
pause
