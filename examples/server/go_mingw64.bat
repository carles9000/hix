@echo off

if exist hix.exe del hix.exe
if exist hix.res del hix.res

set hix=c:\hix.project\hix.pro

set ccdir=c:\gcc85\mingw64
set hbdir=c:\harbour
set hbgcc=%hbdir%\bin\win\mingw64
set include=%include%;%hbdir%\include;%hix%\src\include;%ccdir%\include;
set HB_USER_LIBPATHS=%hbgcc%\lib;%hix%;%hix%\dll\mingw64
set lib=%lib%;%hbdir%\lib
set path=%path%;c:\windows\system32;c:\windows;%hbgcc%;%hbdir%;%ccdir%\bin


hbmk2 hix.hbp -comp=mingw64

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
