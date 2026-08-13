@echo off

if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" amd64


if exist app.exe del app.exe

if not exist "app.res" (	
	rc -r app.rc
)

set hix=c:\hix.project\hix.pro

set hbdir=c:\harbour
set hbmsvc=%hbdir%\bin\win\msvc64
set include=%include%;%hbdir%\include;%hix%\src\include
set lib=%lib%;%hbdir%\lib
set path=%path%;c:\windows\system32;c:\windows;%hbmsvc%;%hbdir%


@echo Compiling Webservice !

hbmk2 app.hbp -comp=msvc64

if errorlevel 1 goto error

if exist app.lib del app.lib
if exist app.exp del app.exp
if exist app.res del app.res

@cls
app.exe

goto exit

:error
echo *** Error de compilacion
pause

:exit
