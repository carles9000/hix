@echo off
REM ============================================================
REM  HIX AI System -- install.bat
REM  Wrapper for install.ps1 that bypasses PowerShell execution
REM  policy so users don't need to remember the incantation.
REM
REM  Usage:
REM    install.bat C:\path\to\project
REM    install.bat C:\path\to\project /copy    (force copy, no symlinks)
REM ============================================================
setlocal

if "%~1"=="" (
    echo.
    echo Usage: install.bat ^<TargetProjectDir^> [/copy]
    echo.
    echo   TargetProjectDir  Path to the project where CLAUDE.md will be wired.
    echo   /copy             Optional. Skip symlinks and copy files instead.
    echo.
    exit /b 1
)

set "TARGET=%~1"
set "MODE="
if /I "%~2"=="/copy" set "MODE=-ForceCopy"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Target "%TARGET%" %MODE%
exit /b %ERRORLEVEL%
