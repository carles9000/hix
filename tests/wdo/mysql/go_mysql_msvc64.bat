@echo off
REM ------------------------------------------------------------------
REM  tests/wdo/mysql/go_mysql_msvc64.bat - compila y ejecuta test_wdo_mysql
REM
REM  Requiere Visual Studio 2022 (vcvarsall.bat).
REM  Config de conexion opcional via env vars:
REM    set WDO_MYSQL_HOST=127.0.0.1
REM    set WDO_MYSQL_USER=root
REM    set WDO_MYSQL_PWD=xxxxx
REM    set WDO_MYSQL_DB=test
REM    set WDO_MYSQL_PORT=3306
REM    set WDO_PATH_MYSQL=C:\ruta\           (con backslash final)
REM ------------------------------------------------------------------

setlocal

set TESTNAME=test_wdo_mysql

REM  Inicializa el entorno MSVC64 (silencioso)
if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" amd64 >nul 2>&1

REM  Anadir Harbour + msvc64 al PATH
REM  Raiz HIX relativa al .bat (tests/wdo/mysql -> 3 niveles arriba)
pushd %~dp0..\..\..
set hix=%CD%
popd
set hbdir=c:\harbour
set hbmsvc=%hbdir%\bin\win\msvc64
set include=%include%;%hbdir%\include;%hix%\src\include
set lib=%lib%;%hbdir%\lib
set path=%hix%\resources\wdo\mysql\dll;%hix%\tests\wdo;c:\windows\system32;c:\windows;%hbmsvc%;%hbdir%;%path%

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
