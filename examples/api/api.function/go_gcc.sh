#!/usr/bin/env bash
# --------------------------------------------------------------
# go_gcc.sh - Build and run HIX example api.function on Linux/gcc
#
# Linux equivalent of go_msvc64.bat / go_mingw64.bat. Compiles
# examples/api/api.function/app.hbp against libhix_server.a and (if compile
# succeeds) executes the resulting binary.
#
# Usage:
#   ./go_gcc.sh                          build + run
#   ./go_gcc.sh --port 8080              build + run with args
#   HB_ROOT=/opt/harbour ./go_gcc.sh
# --------------------------------------------------------------

set -e
cd "$(dirname "$(readlink -f "$0")")"

: "${HB_ROOT:=$HOME/harbour-core}"
export HB_ROOT   # needed if app.hbp references ${HB_ROOT}/... paths

HBMK2="$HB_ROOT/bin/linux/gcc/hbmk2"
if [ ! -x "$HBMK2" ]; then
    echo "ERROR: hbmk2 not found at $HBMK2" >&2
    echo "Set HB_ROOT to your Harbour build directory." >&2
    exit 1
fi

export PATH="$HB_ROOT/bin/linux/gcc:$PATH"

# ${hix} in app.hbp expands from this env var (-L${hix}, -i${hix}/src/include).
export hix="$(cd ../../.. && pwd)"

# HIX compiles www/controllers, www/middlewares and www/loaders at
# runtime via hb_CompileFromBuf. The preprocessor (src/hix_prepro.prg)
# looks up standard Harbour headers via $HB_INCLUDE — without it,
# dynamic .prg files that use hbclass.ch / hbmemory.ch / etc. fail to
# compile silently and the router returns 403 for their routes.
export HB_INCLUDE="$HB_ROOT/include${HB_INCLUDE:+:$HB_INCLUDE}"

# ------------------------------------------------------------
# It is very important to validate the HBX files, otherwise it
# will produce silent errors.
# ------------------------------------------------------------

if [ ! -f "$hix/hix_server.hbx" ]; then
    echo "*** ERROR: $hix/hix_server.hbx not found." >&2
    echo "    ../../../go_lib_gcc.sh" >&2
    exit 1
fi
if [ ! -f "$HB_ROOT/include/harbour.hbx" ]; then
    echo "*** ERROR: $HB_ROOT/include/harbour.hbx not found." >&2
    echo "    Check your Harbour installation at $HB_ROOT." >&2
    exit 1
fi
if [ ! -f "$hix/lib/gcc/libhix_server.a" ]; then
    echo "*** ERROR: $hix/lib/gcc/libhix_server.a not found." >&2
    exit 1
fi

# ------------------------------------------------------------

# Remove previous binary so a link failure doesn't silently re-run stale.
rm -f app

"$HBMK2" app.hbp

# Windows-only intermediate artifacts (harmless if absent).
rm -f app.exp app.lib app.res

BIN="./app"
if [ ! -x "$BIN" ]; then
    echo "ERROR: $BIN not produced." >&2
    exit 1
fi

echo
"$BIN" "$@"
