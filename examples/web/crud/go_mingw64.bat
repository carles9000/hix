@echo off

if exist app.exe del app.exe
if exist app.res del app.res

set hix=%~dp0..\..\..

set ccdir=c:\gcc85\mingw64
set hbdir=c:\harbour
set hbgcc=%hbdir%\bin\win\mingw64
set include=%include%;%hbdir%\include;%hix%\src\include;%ccdir%\include;
set HB_USER_LIBPATHS=%hbgcc%\lib;%hix%;%hix%\dll\mingw64
set lib=%lib%;%hbdir%\lib
set path=%path%;c:\windows\system32;c:\windows;%hbgcc%;%hbdir%;%ccdir%\bin

rem ------------------------------------------------------------
rem It is very important to validate the HBX files, otherwise it
rem will produce silent errors.
rem ------------------------------------------------------------

if not exist "%hix%\hix_server.hbx" (
	echo *** ERROR: %hix%\hix_server.hbx not found.
	echo     go_lib_mingw64.bat.
	goto error
)
if not exist "%hbdir%\include\harbour.hbx" (
	echo *** ERROR: %hbdir%\include\harbour.hbx not found.
	echo     Check your Harbour installation at %hbdir%.
	goto error
)
if not exist "%hix%\lib\mingw64\libhix_server.a" (
	echo *** ERROR: %hix%\lib\mingw64\libhix_server.a not found.
	goto error
)

rem ------------------------------------------------------------

hbmk2 app.hbp -comp=mingw64

if errorlevel 1 goto error

if exist app.exp del app.exp
if exist app.lib del app.lib
if exist app.res del app.res

@cls
app.exe

goto exit

:error
pause


:exit
