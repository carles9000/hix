@echo off

if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" amd64

set hbdir=c:\harbour
set include=%include%;%hbdir%\include
set lib=%lib%;%hbdir%\lib
set path=%path%;c:\windows\system32;c:\windows;%hbdir%;%hbdir%\bin

if exist hix_server.hbx (
   hbmk2 hix_server.hbp  -comp=msvc64
) else (
   echo Building hix_server.hbx wait...
   hbmk2 hix_server.hbp  -comp=msvc64 -hbx=hix_server.hbx
)

pause




