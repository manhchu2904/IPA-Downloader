#!/usr/bin/env bash
set -euo pipefail

# Builds:
#   1) iOS/Frameworks/libunicorn.a  (Unicorn 2.1.4 patched for iOS arm64, required by majd/ipatool SAP signer)
#   2) iOS/Frameworks/Ipatoolbridge.xcframework (Go core bridge bound via gomobile)
#
# Must be run on macOS with Xcode Command Line Tools, Go 1.26+, cmake, and gomobile installed.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORKS_DIR="$ROOT_DIR/iOS/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
BUILD_DIR="$(mktemp -d /tmp/dlipa2-build.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "==> [1/3] Building patched Unicorn 2.1.4 (libunicorn.a) for iOS arm64..."
UNICORN_TAR="$BUILD_DIR/unicorn-2.1.4.tar.gz"
curl -fL --retry 3 \
  https://github.com/unicorn-engine/unicorn/archive/refs/tags/2.1.4.tar.gz \
  -o "$UNICORN_TAR"
echo "ea8863f095a0136388694e5a6063afd9bb7650e30243dd6251af59c5ce5601f4  $UNICORN_TAR" | shasum -a 256 -c -
tar -xzf "$UNICORN_TAR" -C "$BUILD_DIR"

patch -d "$BUILD_DIR/unicorn-2.1.4" -p1 < "$ROOT_DIR/scripts/patches/unicorn-ios.patch"

ARCHFLAGS='-arch arm64' cmake \
  -S "$BUILD_DIR/unicorn-2.1.4" \
  -B "$BUILD_DIR/unicorn-build" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT="$SDKROOT" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_C_FLAGS='-target arm64-apple-ios15.0' \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DUNICORN_ARCH=x86 \
  -DUNICORN_BUILD_TESTS=OFF \
  -DUNICORN_INSTALL=OFF

cmake --build "$BUILD_DIR/unicorn-build" --parallel "$(sysctl -n hw.ncpu)"
cp "$BUILD_DIR/unicorn-build/libunicorn.a" "$FRAMEWORKS_DIR/libunicorn.a"

echo "==> [2/3] Syncing Core Go dependencies with latest majd/ipatool/v2..."
cd "$ROOT_DIR/Core"
go get github.com/majd/ipatool/v2@main
go mod tidy
go get golang.org/x/mobile/bind@latest

echo "==> [3/3] Building Ipatoolbridge.xcframework via gomobile..."
rm -rf "$FRAMEWORKS_DIR/Ipatoolbridge.xcframework"
gomobile bind \
  -target=ios/arm64 \
  -iosversion=15.0 \
  -o "$FRAMEWORKS_DIR/Ipatoolbridge.xcframework" \
  ./ipatoolbridge

echo "==> Done! Outputs:"
echo "    - $FRAMEWORKS_DIR/libunicorn.a"
echo "    - $FRAMEWORKS_DIR/Ipatoolbridge.xcframework"
