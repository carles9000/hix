@echo off
cls

set ccdir=c:\gcc85\mingw64
set hbdir=c:\harbour
set hbgcc=%hbdir%\bin\win\mingw64
set include=%include%;%hbdir%\include;%ccdir%\include;
set HB_USER_LIBPATHS=%hbgcc%\lib
set lib=%lib%;%hbgcc%\lib;%ccdir%\lib;%ccdir%\x86_64-w64-mingw32\lib;
set path=%path%;c:\windows\system32;c:\windows;%hbgcc%;%hbdir%;%ccdir%\bin;


if exist hix_server.hbx (
   hbmk2 hix_server.hbp  -comp=mingw64
) else (
   echo Building hix_server.hbx wait...
   hbmk2 hix_server.hbp  -comp=mingw64 -hbx=hix_server.hbx
)

pause




