#!/usr/bin/env bash
# --------------------------------------------------------------
# go_lib.sh - Compile hix_server library on Linux/gcc
#
# Linux equivalent of go_lib_msvc.bat / go_lib_gcc.bat.
# Produces libhix_server.a in the project root.
#
# Usage:
#   ./go_lib.sh                          incremental build
#   HB_ROOT=/opt/harbour ./go_lib.sh     override Harbour location
#
# Requires: Harbour built or installed at $HB_ROOT (default
# $HOME/harbour-core). Set HB_ROOT to point elsewhere if needed.
# --------------------------------------------------------------

set -e
cd "$(dirname "$(readlink -f "$0")")"

: "${HB_ROOT:=$HOME/harbour-core}"

HBMK2="$HB_ROOT/bin/linux/gcc/hbmk2"
if [ ! -x "$HBMK2" ]; then
    echo "ERROR: hbmk2 not found at $HBMK2" >&2
    echo "Set HB_ROOT to your Harbour build directory." >&2
    exit 1
fi

export PATH="$HB_ROOT/bin/linux/gcc:$PATH"

mkdir -p lib/gcc

if [ -f hix_server.hbx ]; then
    "$HBMK2" hix_server.hbp
else
    echo "Building hix_server.hbx (first time)..."
    "$HBMK2" hix_server.hbp -hbx=hix_server.hbx
fi

if [ -f lib/gcc/libhix_server.a ]; then
    echo
    ls -la lib/gcc/libhix_server.a
    echo "OK: lib/gcc/libhix_server.a built."
else
    echo "ERROR: lib/gcc/libhix_server.a not produced." >&2
    exit 1
fi
