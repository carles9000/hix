#!/usr/bin/env bash
# --------------------------------------------------------------
# go_gcc.sh - Build and run HIX test app on Linux/gcc
#
# Linux equivalent of go_msvc64.bat / go_mingw64.bat. Compiles
# tests/unit/app.hbp against libhix_server.a and (if compile
# succeeds) executes the resulting binary.
#
# Usage:
#   ./go_gcc.sh              build + run in dashboard mode (:8099)
#   ./go_gcc.sh --cli        build + run headless full test suite
#   HB_ROOT=/opt/harbour ./go_gcc.sh
# --------------------------------------------------------------

set -e
cd "$(dirname "$(readlink -f "$0")")"

: "${HB_ROOT:=$HOME/harbour-core}"

HBMK2="$HB_ROOT/bin/linux/gcc/hbmk2"
if [ ! -x "$HBMK2" ]; then
    echo "ERROR: hbmk2 not found at $HBMK2" >&2
    exit 1
fi

export PATH="$HB_ROOT/bin/linux/gcc:$PATH"

# ${hix} in app.hbp expands from this env var.
export hix="$(cd ../.. && pwd)"

# Harbour runtime compiler (hb_compileFromBuf / dispatcher .prg
# handlers) looks up includes via the INCLUDE env var. Point it at
# the Harbour core headers so tests that emit temporary .prg files
# with #include "hbclass.ch" etc. compile at runtime.
export INCLUDE="$HB_ROOT/include${INCLUDE:+:$INCLUDE}"

if [ ! -f "$hix/lib/gcc/libhix_server.a" ]; then
    echo "ERROR: $hix/lib/gcc/libhix_server.a not found. Run ../../go_lib_gcc.sh first." >&2
    exit 1
fi

"$HBMK2" app.hbp

# Windows-only intermediate artifacts (harmless if absent).
rm -f app.exp app.lib

BIN="./app"
if [ ! -x "$BIN" ]; then
    echo "ERROR: $BIN not produced." >&2
    exit 1
fi

# Auto-generate SSL test certificates on first run.
if [ ! -f hix_test.crt ] || [ ! -f hix_test.key ]; then
    if [ -x ./make_test_cert.sh ]; then
        echo "First run: generating SSL test certificates..."
        ./make_test_cert.sh >/dev/null
    fi
fi

echo
"$BIN" "$@"
