@echo off
REM ============================================================
REM  HIX AI System -- uninstall.bat
REM  Wrapper for uninstall.ps1.
REM
REM  Usage:
REM    uninstall.bat C:\path\to\project
REM ============================================================
setlocal

if "%~1"=="" (
    echo.
    echo Usage: uninstall.bat ^<TargetProjectDir^>
    echo.
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" -Target "%~1"
exit /b %ERRORLEVEL%
