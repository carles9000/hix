#!/usr/bin/env bash
# --------------------------------------------------------------
# make_test_cert.sh - Generate self-signed cert for SSL tests
#
# Linux equivalent of make_test_cert.bat. Uses the system openssl
# (comes with libssl-dev or the openssl apt package).
# --------------------------------------------------------------

set -e
cd "$(dirname "$(readlink -f "$0")")"

if ! command -v openssl >/dev/null 2>&1; then
    echo "ERROR: openssl not found. Install with: sudo apt install openssl" >&2
    exit 1
fi

rm -f hix_test.key hix_test.crt

openssl req -x509 -newkey rsa:2048 \
    -keyout hix_test.key -out hix_test.crt \
    -days 365 -nodes -subj "/CN=localhost"

echo
echo "Certificados generados:"
echo "  hix_test.key  (clave privada)"
echo "  hix_test.crt  (certificado)"
