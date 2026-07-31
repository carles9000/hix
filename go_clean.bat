@echo off
echo =========================================================
echo         DELETE FILES GENERATED. RESTORE ORIGINAL
echo =========================================================
echo.

set /p CONFIRM="We started deleting generated files? "

if /i "%CONFIRM%" NEQ "Y" if /i "%CONFIRM%" NEQ "S" (
    echo.
    echo Process aborted by the user. Exit
    echo.
    pause
    exit /b
)

rd /S /Q .hbmk
rd /S /Q .logs
rd /S /Q .cached
del hix_app.exe 
del hix_server.hbx 
del hix_server.lib 
del hix.json

pause