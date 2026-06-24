#!/usr/bin/env bash
#
# Build TDLib's JSON interface (libtdjson.so) for Android from the external/td
# submodule, linking against the OpenSSL built by build-openssl.sh.
#
# Output: build/android/tdlib/libs/<abi>/libtdjson.so (+ .so.debug)
#
# Env overrides:
#   ANDROID_STL=...    c++_static (default) or c++_shared
#   ANDROID_ABIS=...   space-separated list of ABIs to build
#   BUILD_DIR=...      output root (default: <repo>/build/android)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
resolve_ndk

ANDROID_STL="${ANDROID_STL:-c++_static}"

if [[ ! -d "$TD_SRC_DIR" ]] || [[ -z "$(ls -A "$TD_SRC_DIR" 2>/dev/null)" ]]; then
  echo "Error: TDLib submodule is empty at $TD_SRC_DIR" >&2
  echo "  Run: git submodule update --init --recursive" >&2
  exit 1
fi

if [[ ! -d "$OPENSSL_INSTALL_DIR" ]]; then
  echo "Error: OpenSSL not built ($OPENSSL_INSTALL_DIR missing)." >&2
  echo "  Run scripts/android/build-openssl.sh first." >&2
  exit 1
fi

echo "TDLib source : $TD_SRC_DIR @ $(git -C "$TD_SRC_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
echo "NDK          : $NDK_ROOT"
echo "ABIs         : ${ANDROID_ABIS[*]}"
echo "Min API      : $ANDROID_MIN_API"
echo "STL          : $ANDROID_STL"

# --- Phase A: generate TL source files on the host ---------------------------
# Cross-compilation can't run the code generators, so produce them natively
# first. OpenSSL is not required for this step (TD_GENERATE_SOURCE_FILES).
echo ""
echo "=== Generating TDLib source files (host) ==="
GEN_DIR="$BUILD_DIR/td-generate"
cmake -DTD_ANDROID_JSON=ON -DTD_GENERATE_SOURCE_FILES=ON \
  -S "$TD_ANDROID_DIR" -B "$GEN_DIR"
cmake --build "$GEN_DIR"

# --- Phase B: cross-compile libtdjson.so per ABI -----------------------------
for ABI in "${ANDROID_ABIS[@]}"; do
  echo ""
  echo "=== Building libtdjson.so for $ABI ==="
  BDIR="$BUILD_DIR/td-$ABI"

  cmake \
    -DCMAKE_TOOLCHAIN_FILE="$NDK_CMAKE_TOOLCHAIN" \
    -DOPENSSL_ROOT_DIR="$OPENSSL_INSTALL_DIR/$ABI" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DANDROID_ABI="$ABI" \
    -DANDROID_STL="$ANDROID_STL" \
    -DANDROID_PLATFORM="android-$ANDROID_MIN_API" \
    -DCMAKE_SHARED_LINKER_FLAGS="$PAGE_SIZE_LDFLAG" \
    -DTD_ANDROID_JSON=ON \
    -GNinja \
    -S "$TD_ANDROID_DIR" -B "$BDIR"

  cmake --build "$BDIR" --target tdjson

  DEST="$TDLIB_OUT_DIR/libs/$ABI"
  mkdir -p "$DEST"
  cp "$BDIR/td/libtdjson.so" "$DEST/libtdjson.so.debug"
  "$NDK_TOOLCHAIN/bin/llvm-strip" --strip-debug --strip-unneeded \
    "$DEST/libtdjson.so.debug" -o "$DEST/libtdjson.so"
done

echo ""
echo "TDLib build complete -> $TDLIB_OUT_DIR/libs"
