#!/usr/bin/env bash
#
# Build OpenSSL (static) for Android from the external/openssl submodule.
# The static libs are linked into libtdjson.so, so we never build shared OpenSSL.
#
# Output: build/android/openssl/<abi>/{lib,include}
#
# Env overrides:
#   ANDROID_ABIS=...   space-separated list of ABIs to build
#   BUILD_DIR=...      output root (default: <repo>/build/android)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
resolve_ndk

if [[ ! -d "$OPENSSL_SRC_DIR" ]] || [[ -z "$(ls -A "$OPENSSL_SRC_DIR" 2>/dev/null)" ]]; then
  echo "Error: OpenSSL submodule is empty at $OPENSSL_SRC_DIR" >&2
  echo "  Run: git submodule update --init --recursive" >&2
  exit 1
fi

OPENSSL_REV="$(git -C "$OPENSSL_SRC_DIR" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
echo "OpenSSL source : $OPENSSL_SRC_DIR @ $OPENSSL_REV"
echo "NDK            : $NDK_ROOT"
echo "ABIs           : ${ANDROID_ABIS[*]}"
echo "Min API        : $ANDROID_MIN_API"

export ANDROID_NDK_HOME="$NDK_ROOT"   # OpenSSL 1.1.1 reads ANDROID_NDK_HOME
export PATH="$NDK_TOOLCHAIN/bin:$PATH"

if ! clang --help >/dev/null 2>&1; then
  echo "Error: failed to run clang from NDK ($NDK_TOOLCHAIN/bin)." >&2
  exit 1
fi

# Export a pristine copy of the submodule so the build never dirties it.
SRC_COPY="$BUILD_DIR/openssl-src"
rm -rf "$SRC_COPY"
mkdir -p "$SRC_COPY"
git -C "$OPENSSL_SRC_DIR" archive HEAD | tar -x -C "$SRC_COPY"

cd "$SRC_COPY"

for ABI in "${ANDROID_ABIS[@]}"; do
  echo ""
  echo "=== Building OpenSSL for $ABI ==="
  TARGET="$(openssl_target_for_abi "$ABI")"

  EXTRA=""
  [[ "$ABI" == "armeabi-v7a" ]] && EXTRA="-D__ARM_MAX_ARCH__=8"

  # shellcheck disable=SC2086  # intentional word-splitting for $EXTRA
  ./Configure "$TARGET" no-shared \
    -U__ANDROID_API__ -D__ANDROID_API__="$ANDROID_MIN_API" $EXTRA

  # Allow the linker to drop unused functions/data.
  sed -i.bak 's/-O3/-O3 -ffunction-sections -fdata-sections/g' Makefile

  make depend -s
  make -j"$(num_cpus)" -s

  DEST="$OPENSSL_INSTALL_DIR/$ABI"
  rm -rf "$DEST"
  mkdir -p "$DEST/lib"
  cp libcrypto.a libssl.a "$DEST/lib/"
  cp -R include "$DEST/"

  make distclean
done

cd "$REPO_ROOT"
rm -rf "$SRC_COPY"

echo ""
echo "OpenSSL build complete -> $OPENSSL_INSTALL_DIR"
