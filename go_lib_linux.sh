#!/bin/bash
# ============================================================
# Script de compilación de librerías HIX para Linux
# Equivalente a go_lib_msvc.bat / go_lib_gcc.bat
# ============================================================

# Si Harbour no está en el PATH global (/usr/local/bin),
# se busca automáticamente en ~/harbour-core o la variable $HB_DIR
HB_DIR="${HB_DIR:-$HOME/harbour-core}"
if [ -d "$HB_DIR/bin/linux/gcc" ]; then
    export PATH="$HB_DIR/bin/linux/gcc:$PATH"
    export LD_LIBRARY_PATH="$HB_DIR/lib/linux/gcc:${LD_LIBRARY_PATH:-}"
    export HB_USER_LIBPATHS="$HB_DIR/lib/linux/gcc"
fi

# Verificar disponibilidad de hbmk2
if ! command -v hbmk2 &> /dev/null; then
    echo "[ERROR] No se encontró el ejecutable 'hbmk2' en el PATH ni en $HB_DIR/bin/linux/gcc."
    echo "Verifica la ruta de Harbour antes de continuar."
    exit 1
fi

echo "==> Iniciando compilación de HIX Server Library para Linux..."

if [ -f "hix_server.hbx" ]; then
    hbmk2 hix_server.hbp "$@"
else
    echo "==> Generando hix_server.hbx y compilando..."
    hbmk2 hix_server.hbp -hbx=hix_server.hbx "$@"
fi

BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo "==> [OK] Librería HIX Server compilada correctamente."
else
    echo "==> [ERROR] Ocurrió un error al compilar (Código: $BUILD_STATUS)."
fi

exit $BUILD_STATUS
