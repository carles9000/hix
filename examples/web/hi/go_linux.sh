#!/bin/bash
# ============================================================
# Script de compilación y ejecución de HIX Web Hi para Linux
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

echo "==> Compilando HIX Web Hi (examples/web/hi)..."

hbmk2 app.hbp

BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo "==> [OK] App compilada con éxito."
    echo "==> Ejecutable generado: ./app"
    if [ "$1" == "--run" ] || [ "$1" == "-r" ]; then
        echo "==> Iniciando aplicación..."
        ./app
    fi
else
    echo "==> [ERROR] Ocurrió un error al compilar la app (Código: $BUILD_STATUS)."
fi

exit $BUILD_STATUS
