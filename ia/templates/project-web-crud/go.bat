@echo off

if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" amd64

set hix={{HIX_PATH}}
set hbdir=c:\harbour
set include=%include%;%hbdir%\include;%hix%\src\include
set lib=%lib%;%hbdir%\lib;%hix%
set path=%path%;c:\windows\system32;c:\windows;%hbdir%;%hbdir%\bin;%hbdir%\dll\msvc64;%hix%;%hix%\dll\msvc

rem ---- serve mode: run only, skip build (used by tests/run.ps1) ----
if /I "%1"=="serve" (
    if not exist app.exe (
        echo *** app.exe not found -- run "go.bat build" first
        exit /b 1
    )
    .\app.exe
    goto exit
)

if exist app.exe del app.exe

@echo Compiling {{PROJECT_NAME}}...
hbmk2 app.hbp -comp=msvc64

if errorlevel 1 goto error

if exist app.lib del app.lib
if exist app.exp del app.exp

if /I "%1"=="build" goto exit

@cls
.\app.exe

goto exit

:error
echo *** Compile error
pause

:exit
