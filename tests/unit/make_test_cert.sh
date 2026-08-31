#!/bin/bash
# ============================================================
# Genera certificados autofirmados para tests SSL de HIX en Linux
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v openssl &> /dev/null; then
    echo "[ERROR] No se encontró 'openssl' instalado en el sistema."
    exit 1
fi

rm -f hix_test.key hix_test.crt

openssl req -x509 -newkey rsa:2048 -keyout hix_test.key -out hix_test.crt \
    -days 365 -nodes -subj "/CN=localhost"

if [ $? -eq 0 ]; then
    echo "==> Certificados SSL de prueba generados correctamente:"
    echo "    - hix_test.key (clave privada)"
    echo "    - hix_test.crt (certificado público)"
else
    echo "[ERROR] Falló la generación de certificados SSL."
    exit 1
fi
