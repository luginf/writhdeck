#!/bin/sh
# Cross-compile Tcl 8.6 as a static library for Android.
# Run from android/ :
#   ./tools/build-tcl-android.sh arm64-v8a
#   ./tools/build-tcl-android.sh x86_64
#   ./tools/build-tcl-android.sh armeabi-v7a   (optional)
#
# Output: android/tcl-android/<ABI>/install/lib/libtcl8.6.a
# Tcl sources must be unpacked in android/ as tcl8.6.15/ :
#   wget https://prdownloads.sourceforge.net/tcl/tcl8.6.15-src.tar.gz
#   tar xzf tcl8.6.15-src.tar.gz

set -e

ABI=${1:-arm64-v8a}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."   # android/

NDK_ROOT="${ANDROID_NDK_ROOT:-}"
if [ -z "$NDK_ROOT" ]; then
    NDK_BASE="$HOME/Android/Sdk/ndk"
    NDK_ROOT="$NDK_BASE/$(ls "$NDK_BASE" 2>/dev/null | sort -V | tail -1)"
fi
API=26
TCL_SRC_DIR="${TCL_SRC_DIR:-$ROOT/tcl8.6.15/unix}"
OUT="$ROOT/tcl-android/$ABI"

# Sanity checks
if [ ! -d "$TCL_SRC_DIR" ]; then
    echo "ERROR: Tcl sources not found at $TCL_SRC_DIR"
    echo "  wget https://prdownloads.sourceforge.net/tcl/tcl8.6.15-src.tar.gz"
    echo "  tar xzf tcl8.6.15-src.tar.gz   (run from android/)"
    exit 1
fi
TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"
if [ ! -f "$TOOLCHAIN/bin/clang" ]; then
    echo "ERROR: NDK toolchain not found at $TOOLCHAIN"
    echo "  Set ANDROID_NDK_ROOT or install NDK via Android Studio -> SDK Manager"
    exit 1
fi

case $ABI in
    arm64-v8a)    TRIPLE=aarch64-linux-android ;;
    armeabi-v7a)  TRIPLE=armv7a-linux-androideabi ;;
    x86_64)       TRIPLE=x86_64-linux-android ;;
    *) echo "Unknown ABI: $ABI"; exit 1 ;;
esac

SYSROOT="$TOOLCHAIN/sysroot"

# Use clang directly with --target rather than the NDK wrapper scripts.
# This avoids configure failing if the wrapper's #!/usr/bin/env bash is
# exec'd in a restricted environment.
CC="$TOOLCHAIN/bin/clang"
AR="$TOOLCHAIN/bin/llvm-ar"
RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
# -fPIC is required: libtcl8.6.a is linked into libwrithdeck.so (shared lib)
TARGET_FLAGS="--target=${TRIPLE}${API} --sysroot=$SYSROOT -fPIC"

echo "==> Building Tcl 8.6 for $ABI (API $API)"
echo "    NDK:     $NDK_ROOT"
echo "    Clang:   $CC"
echo "    Output:  $OUT/install"

# Clean previous failed configure if any
rm -f "$OUT/config.log" "$OUT/Makefile" 2>/dev/null || true
mkdir -p "$OUT" && cd "$OUT"

"$TCL_SRC_DIR/configure" \
    --host="$TRIPLE" \
    --build="$(uname -m)-linux-gnu" \
    --prefix="$OUT/install" \
    --disable-shared \
    --disable-load \
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CFLAGS="$TARGET_FLAGS" \
    LDFLAGS="$TARGET_FLAGS" \
    tcl_cv_strtod_buggy=ok \
    ac_cv_func_getpwuid_r=no \
    ac_cv_func_getpwnam_r=no

make -j"$(nproc)"
make install

echo ""
echo "==> Done: $OUT/install/lib/libtcl8.6.a"
