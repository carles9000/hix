@echo off

if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" (
    call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" amd64
)

if exist app.exe del app.exe


if not exist "app.res" (
	rc -r app.rc
)

set hix=%~dp0..\..\..

set hbdir=c:\harbour
set hbmsvc=%hbdir%\bin\win\msvc64
set include=%include%;%hbdir%\include;%hix%\src\include
set lib=%lib%;%hbdir%\lib
set path=%path%;c:\windows\system32;c:\windows;%hbmsvc%;%hbdir%

rem ------------------------------------------------------------
rem It is very important to validate the HBX files, otherwise it
rem will produce silent errors.
rem ------------------------------------------------------------

if not exist "%hix%\hix_server.hbx" (
	echo *** ERROR: %hix%\hix_server.hbx not found.
	echo     go_lib_msvc64.bat.
	goto error
)
if not exist "%hbdir%\include\harbour.hbx" (
	echo *** ERROR: %hbdir%\include\harbour.hbx not found.
	echo     Check your Harbour installation at %hbdir%.
	goto error
)
if not exist "%hix%\lib\msvc64\hix_server.lib" (
	echo *** ERROR: %hix%\lib\msvc64\hix_server.lib not found.
	goto error
)

rem ------------------------------------------------------------

hbmk2 app.hbp -comp=msvc64

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
