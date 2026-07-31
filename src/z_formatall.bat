@echo off
rem -----------------------------------------------------------
rem  z_formatall.bat
rem  Formatea recursivamente todos los .prg en src/ y subdirs
rem  usando bin/format/hbformat.exe + bin/format/hbformat.cfg
rem  Cada fichero original se guarda como .bak
rem -----------------------------------------------------------

setlocal enabledelayedexpansion

set FMT=%~dp0..\bin\format\hbformat.exe
set CFG=%~dp0..\bin\format\hbformat.cfg

if not exist "%FMT%" (
   echo [ERROR] No se encuentra %FMT%
   exit /b 1
)
if not exist "%CFG%" (
   echo [ERROR] No se encuentra %CFG%
   exit /b 1
)

set /a nOk=0
set /a nKo=0

for /r "%~dp0" %%F in (*.prg) do (
   echo --- %%F
   "%FMT%" @"%CFG%" "%%F"
   if errorlevel 1 (
      set /a nKo+=1
   ) else (
      set /a nOk+=1
   )
)

echo.
echo ==========================================================
echo   Formateados OK : !nOk!
echo   Con error      : !nKo!
echo ==========================================================

endlocal
pause 
