# Readme !

1.- Adjust the paths of the go.bat compilation file

set hix=...
set hbdir=c:\harbour
set include=%include%;%hbdir%\include;%hix%\src\include
set lib=%lib%;%hbdir%\lib;%hix%
set path=%path%;c:\windows\system32;c:\windows;%hbdir%;%hbdir%\bin;%hix%

2.- Copy .\dll\*.dll to server path

