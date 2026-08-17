@echo off
REM Genera certificado autofirmado para tests SSL
REM Requiere OpenSSL de vcpkg en c:\vcpkg\packages\openssl_x64-windows\tools\openssl\

cd /d %~dp0

set OPENSSL=c:\vcpkg\packages\openssl_x64-windows\tools\openssl\openssl.exe

if not exist "%OPENSSL%" (
  echo ERROR: No se encuentra OpenSSL en %OPENSSL%
  exit /b 1
)

if exist hix_test.key del hix_test.key
if exist hix_test.crt del hix_test.crt

"%OPENSSL%" req -x509 -newkey rsa:2048 -keyout hix_test.key -out hix_test.crt ^
  -days 365 -nodes -subj "/CN=localhost"

if errorlevel 1 (
  echo ERROR: Fallo la generacion del certificado
  exit /b 1
)

echo.
echo Certificados generados:
echo   hix_test.key  (clave privada)
echo   hix_test.crt  (certificado)

echo Certificados en tests.master\ listos para usar.

pause
