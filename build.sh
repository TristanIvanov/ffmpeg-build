#!/bin/bash
# Build FFmpeg with OpenSSL for macOS (local build script)
# Usage: ./build.sh [ffmpeg_version]
# Example: ./build.sh 7.1.1

set -euo pipefail

FFMPEG_VERSION="${1:-7.1.1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_DIR="${SCRIPT_DIR}/output"

echo "=== Building FFmpeg ${FFMPEG_VERSION} with OpenSSL ==="
echo "Build dir: ${BUILD_DIR}"
echo "Output dir: ${OUTPUT_DIR}"

# Check dependencies
for dep in brew pkg-config nasm make; do
  if ! command -v "$dep" &> /dev/null; then
    echo "Missing dependency: $dep"
    exit 1
  fi
done

# Install OpenSSL via Homebrew
brew install openssl pkg-config nasm

OPENSSL_DIR=$(brew --prefix openssl)
echo "OpenSSL dir: ${OPENSSL_DIR}"

# Download source
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
  echo "Downloading FFmpeg ${FFMPEG_VERSION}..."
  curl -L "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o ffmpeg.tar.xz
  tar xf ffmpeg.tar.xz
  rm ffmpeg.tar.xz
fi

cd "ffmpeg-${FFMPEG_VERSION}"

# Configure
export PKG_CONFIG_PATH="${OPENSSL_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

./configure \
  --enable-openssl \
  --enable-nonfree \
  --enable-gpl \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libmp3lame \
  --enable-libopus \
  --enable-libvorbis \
  --disable-doc \
  --disable-ffplay \
  --disable-ffprobe \
  --enable-static \
  --disable-shared \
  --extra-cflags="-I${OPENSSL_DIR}/include" \
  --extra-ldflags="-L${OPENSSL_DIR}/lib" \
  --pkg-config-flags="--static"

# Build
make -j"$(sysctl -n hw.ncpu)"

# Verify
echo ""
echo "=== Build complete ==="
echo "TLS backend check:"
./ffmpeg -version 2>&1 | grep -i "openssl\|configuration" || true

# Package
mkdir -p "${OUTPUT_DIR}"
cp ffmpeg "${OUTPUT_DIR}/ffmpeg"
chmod +x "${OUTPUT_DIR}/ffmpeg"

ARCH=$(uname -m)
cd "${OUTPUT_DIR}"
zip "ffmpeg-${FFMPEG_VERSION}-macos-${ARCH}.zip" ffmpeg

echo ""
echo "=== Output ==="
file "${OUTPUT_DIR}/ffmpeg"
echo "ZIP: ${OUTPUT_DIR}/ffmpeg-${FFMPEG_VERSION}-macos-${ARCH}.zip"
echo ""
echo "To use with Atalant Streamer, copy the ffmpeg binary to:"
echo "  src-tauri/target/debug/ffmpeg"
echo "  (or next to the .app bundle in production)"
