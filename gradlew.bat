@echo off
setlocal

set "DIR=%~dp0"
if "%DIR%"=="" set "DIR=."

REM Keep Gradle caches inside the repo so shell sessions behave consistently.
if "%GRADLE_USER_HOME%"=="" set "GRADLE_USER_HOME=%DIR%.gradle-user-home"

REM Prefer a local Chocolatey Gradle install so we do not depend on PATH or wrapper downloads.
set "LOCAL_GRADLE=%ProgramData%\chocolatey\lib\gradle\tools\gradle-9.5.0\bin\gradle.bat"

if exist "%LOCAL_GRADLE%" (
  call "%LOCAL_GRADLE%" %*
  exit /b %ERRORLEVEL%
)

REM Fallback to PATH if another Gradle install exists.
where gradle >nul 2>nul
if "%ERRORLEVEL%"=="0" (
  call gradle %*
  exit /b %ERRORLEVEL%
)

echo.
echo ERROR: No usable Gradle installation was found.
echo Expected local install:
echo   %LOCAL_GRADLE%
echo Or a working ^'gradle^' on PATH.
echo.
exit /b 1
