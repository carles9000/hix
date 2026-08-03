@echo off

if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" amd64

set hix=c:\hix.project\hix.pro
set hbdir=c:\harbour
set include=%include%;%hbdir%\include;%hix%\src\include
set lib=%lib%;%hbdir%\lib;%hix%
set path=%path%;c:\windows\system32;c:\windows;%hbdir%;%hbdir%\bin;%hix%

if exist app.exe del app.exe

if not exist "app.res" (
	rc -r app.rc
)


@echo Compiling Fenix.WS.Function !
hbmk2 app.hbp -comp=msvc64

if errorlevel 1 goto error

if exist app.lib del app.lib
if exist app.exp del app.exp

@cls
app.exe

goto exit

:error
echo *** Error de compilacion
pause

:exit
