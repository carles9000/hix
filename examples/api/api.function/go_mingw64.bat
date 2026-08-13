@echo off

if exist app.exe del app.exe

set hix=c:\hix.project\hix.pro

set ccdir=c:\gcc85\mingw64
set hbdir=c:\harbour
set hbgcc=%hbdir%\bin\win\mingw64
set include=%include%;%hbdir%\include;%hix%\src\include;%ccdir%\include;
set HB_USER_LIBPATHS=%hbgcc%\lib;%hix%;%hix%\dll\mingw64
set lib=%lib%;%hbdir%\lib
set path=%path%;c:\windows\system32;c:\windows;%hbgcc%;%hbdir%;%ccdir%\bin


@echo Compiling Webservice !

hbmk2 app.hbp -comp=mingw64

if errorlevel 1 goto compileerror

if exist app.exp del app.exp
if exist app.lib del app.lib
if exist app.res del app.res

@cls
app.exe

goto exit

:compileerror
echo *** Error de compilacion
pause

:exit
