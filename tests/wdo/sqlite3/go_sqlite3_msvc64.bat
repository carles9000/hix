@echo off
REM ------------------------------------------------------------------
REM  tests/wdo/sqlite3/go_sqlite3_msvc64.bat - compila y ejecuta test_wdo_sqlite3
REM
REM  Requiere Visual Studio 2022 (vcvarsall.bat).
REM  Driver nativo (hb_DynCall) sobre sqlcipher.dll runtime.
REM ------------------------------------------------------------------

setlocal

set TESTNAME=test_wdo_sqlite3

REM  Inicializa el entorno MSVC64 (silencioso)
if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" amd64 >nul 2>&1

REM  Anadir Harbour + msvc64 al PATH
REM  Raiz HIX relativa al .bat (tests/wdo/sqlite3 -> 3 niveles arriba)
pushd %~dp0..\..\..
set hix=%CD%
popd
set hbdir=c:\harbour
set hbmsvc=%hbdir%\bin\win\msvc64
set include=%include%;%hbdir%\include;%hix%\src\include
set lib=%lib%;%hbdir%\lib
set path=%hix%\tests\wdo;c:\windows\system32;c:\windows;%hbmsvc%;%hbdir%;%path%

REM  Limpia binario previo
if exist %TESTNAME%.exe del /f /q %TESTNAME%.exe

REM  Compila con msvc64
hbmk2 -comp=msvc64 %TESTNAME%.hbp
if errorlevel 1 (
   echo [ERROR] Compilacion fallida
   exit /b 1
)

REM  Sin --cli: Main hace Inkey(0) al terminar para ver resultados.
REM  Pasar cualquier arg (p.ej. --cli) para automatizar sin pausa.
if not exist %TESTNAME%.exe (
   echo [ERROR] El binario %TESTNAME%.exe no se genero
   endlocal
   exit /b 1
)

echo [RUN] .\%TESTNAME%.exe %1 %2 %3 %4 %5 %6 %7 %8 %9
.\%TESTNAME%.exe %1 %2 %3 %4 %5 %6 %7 %8 %9
set RC=%ERRORLEVEL%
echo [EXIT] errorlevel=%RC%

endlocal
exit /b %RC%
