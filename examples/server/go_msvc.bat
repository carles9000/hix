@echo off

if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" amd64

if exist hix_app.exe del hix_app.exe


if not exist "hix_app.res" (	
	rc -r hix_app.rc
)


set hix=c:\hix.project\hix.pro
set hbdir=c:\harbour
set include=%include%;%hbdir%\include;%hix%\src\include
set lib=%lib%;%hbdir%\lib;%hix%
set path=%path%;c:\windows\system32;c:\windows;%hbdir%;%hbdir%\bin;%hix%

rem set DEBUG_FLAG=-b -DDEBUG

hbmk2 hix_app.hbp -comp=msvc64 
rem pause
if errorlevel 1 goto compileerror

del hix_app.exp
del hix_app.lib
del hix_app.res

@cls
hix_app.exe 

goto exit 

:compileerror

echo *** Error 

pause

:exit