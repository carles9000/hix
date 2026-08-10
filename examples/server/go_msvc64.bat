@echo off

if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" amd64

if exist hix.exe del hix.exe


if not exist "hix.res" (	
	rc -r hix.rc
)

set hix=c:\hix.project\hix.pro

set hbdir=c:\harbour
set hbmsvc=%hbdir%\bin\win\msvc64
set include=%include%;%hbdir%\include;%hix%\src\include
set lib=%lib%;%hbdir%\lib
set path=%path%;c:\windows\system32;c:\windows;%hbmsvc%;%hbdir%

hbmk2 hix.hbp -comp=msvc64 

if errorlevel 1 goto compileerror

if exist hix.exp del hix.exp 
if exist hix.lib del hix.lib
if exist hix.res del hix.res

@cls
hix.exe 

goto exit 

:compileerror
echo *** Error 
pause

:exit