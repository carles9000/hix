@echo off

if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" amd64

set hix=c:\hix.project\hix.pro

set hbdir=c:\harbour
set hbmsvc=%hbdir%\bin\win\msvc64
set include=%include%;%hbdir%\include;%hix%\src\include
set lib=%lib%;%hbdir%\lib
set path=%path%;c:\windows\system32;c:\windows;%hbmsvc%;%hbdir%

hbmk2 app.hbp -comp=msvc64 

if errorlevel 1 goto compileerror

if exist app.exp del app.exp 
if exist app.lib del app.lib


@cls
app.exe 

goto exit 

:compileerror
echo *** Error 
pause

:exit