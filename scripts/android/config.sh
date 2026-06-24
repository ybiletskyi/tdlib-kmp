#!/usr/bin/env bash
#
# Shared configuration and environment resolution for the Android native build.
# Meant to be sourced by build-openssl.sh / build-tdlib.sh.

set -euo pipefail

# --- Paths --------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXTERNAL_DIR="$REPO_ROOT/external"
OPENSSL_SRC_DIR="$EXTERNAL_DIR/openssl"
TD_SRC_DIR="$EXTERNAL_DIR/td"
TD_ANDROID_DIR="$TD_SRC_DIR/example/android"

BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build/android}"
OPENSSL_INSTALL_DIR="$BUILD_DIR/openssl"   # per-ABI: $OPENSSL_INSTALL_DIR/<abi>/{lib,include}
TDLIB_OUT_DIR="$BUILD_DIR/tdlib"           # per-ABI libs: $TDLIB_OUT_DIR/libs/<abi>/libtdjson.so

# --- Build settings -----------------------------------------------------------

# ABIs to build. Override by exporting ANDROID_ABIS="arm64-v8a x86_64" etc.
read -r -a ANDROID_ABIS <<< "${ANDROID_ABIS:-arm64-v8a armeabi-v7a x86_64 x86}"

# Min API level used for the TDLib (.so) build. 28 == Android 9.0.
ANDROID_MIN_API="${ANDROID_MIN_API:-28}"

# 16 KB page alignment for Android 15+ (applied to shared .so links).
PAGE_SIZE_LDFLAG="-Wl,-z,max-page-size=16384"

# --- Host detection -----------------------------------------------------------

case "$OSTYPE" in
  linux*)  HOST_TAG="linux-x86_64" ;;
  darwin*) HOST_TAG="darwin-x86_64" ;;   # NDK ships x86_64 host binaries even on Apple Silicon
  *) echo "Error: unsupported host OS '$OSTYPE' (need Linux or macOS)." >&2; exit 1 ;;
esac

# --- NDK resolution -----------------------------------------------------------
# Populates: NDK_ROOT, NDK_TOOLCHAIN, NDK_CMAKE_TOOLCHAIN

resolve_ndk() {
  if [[ -z "${ANDROID_NDK_ROOT:-}" || ! -d "${ANDROID_NDK_ROOT:-}" ]]; then
    echo "Error: ANDROID_NDK_ROOT is not set to a valid NDK directory." >&2
    exit 1
  fi

  NDK_ROOT="$ANDROID_NDK_ROOT"
  NDK_TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG"
  NDK_CMAKE_TOOLCHAIN="$NDK_ROOT/build/cmake/android.toolchain.cmake"

  if [[ ! -d "$NDK_TOOLCHAIN" ]]; then
    echo "Error: NDK toolchain not found at $NDK_TOOLCHAIN" >&2
    exit 1
  fi
}

# Map Android ABI -> OpenSSL Configure target.
openssl_target_for_abi() {
  case "$1" in
    arm64-v8a)   echo android-arm64 ;;
    armeabi-v7a) echo android-arm ;;
    x86_64)      echo android-x86_64 ;;
    x86)         echo android-x86 ;;
    *) echo "Error: unknown ABI '$1'" >&2; exit 1 ;;
  esac
}

num_cpus() {
  getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4
}
