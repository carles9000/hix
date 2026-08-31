#!/bin/bash
# ============================================================
# Script de compilación y ejecución de tests unitarios de HIX
# ============================================================

HB_DIR="${HB_DIR:-$HOME/harbour-core}"
if [ -d "$HB_DIR/bin/linux/gcc" ]; then
    export PATH="$HB_DIR/bin/linux/gcc:$PATH"
    export LD_LIBRARY_PATH="$HB_DIR/lib/linux/gcc:${LD_LIBRARY_PATH:-}"
    export HB_USER_LIBPATHS="$HB_DIR/lib/linux/gcc"
fi

if ! command -v hbmk2 &> /dev/null; then
    echo "[ERROR] No se encontró 'hbmk2'. Verifica la ruta de Harbour."
    exit 1
fi

echo "==> Compilando tests unitarios (tests/unit)..."

hbmk2 app.hbp

BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo "==> [OK] Tests unitarios compilados con éxito."
    echo "==> Ejecutable generado: ./app"
    if [ "$1" == "--server" ] || [ "$1" == "-s" ]; then
        echo "==> Iniciando servidor de tests web en http://localhost:8099 ..."
        ./app
    elif [ "$1" == "--cli" ] || [ -z "$1" ]; then
        echo "==> Ejecutando suite de tests en modo CLI..."
        ./app --cli
    elif [ "$1" == "--run" ] || [ "$1" == "-r" ]; then
        echo "==> Ejecutando tests..."
        ./app
    fi
else
    echo "==> [ERROR] Ocurrió un error al compilar los tests (Código: $BUILD_STATUS)."
fi

exit $BUILD_STATUS
