#!/bin/bash
# Build FFmpeg with OpenSSL for macOS (local build script)
# Usage: ./build.sh [ffmpeg_version]
# Example: ./build.sh 8.1.2

set -euo pipefail

FFMPEG_VERSION="${1:-8.1.2}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_DIR="${SCRIPT_DIR}/output"

echo "=== Building FFmpeg ${FFMPEG_VERSION} with OpenSSL ==="

# Install dependencies via Homebrew (x264 NOT from brew - we build it from source)
echo "Installing dependencies..."
brew install openssl pkg-config nasm

OPENSSL_DIR=$(brew --prefix openssl)
echo "OpenSSL: ${OPENSSL_DIR}"

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Build x264 from source (static, no X11/libxcb)
if [ ! -d "x264" ]; then
  echo "Building x264 from source..."
  git clone --depth 1 https://code.videolan.org/videolan/x264.git
fi
cd x264
./configure --enable-static --disable-shared --disable-opencl --disable-cli
make -j"$(sysctl -n hw.ncpu)"
sudo make install
cd ..

# Download FFmpeg source
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
  --disable-doc \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-encoders \
  --enable-encoder=aac \
  --enable-encoder=libx264 \
  --enable-encoder=flv \
  --disable-decoders \
  --enable-decoder=aac \
  --enable-decoder=h264 \
  --enable-decoder=pcm_s16le \
  --enable-decoder=pcm_s32le \
  --enable-decoder=mp3 \
  --disable-muxers \
  --enable-muxer=flv \
  --disable-demuxers \
  --enable-demuxer=pcm_s16le \
  --enable-demuxer=pcm_s32le \
  --enable-demuxer=wav \
  --enable-demuxer=mp3 \
  --enable-demuxer=image2 \
  --disable-protocols \
  --enable-protocol=rtmp \
  --enable-protocol=rtmps \
  --enable-protocol=tcp \
  --enable-protocol=udp \
  --enable-protocol=tls \
  --enable-protocol=https \
  --enable-protocol=http \
  --enable-protocol=pipe \
  --enable-protocol=file \
  --enable-static \
  --disable-shared \
  --extra-cflags="-I${OPENSSL_DIR}/include" \
  --extra-ldflags="-L${OPENSSL_DIR}/lib"

# Build
echo "Building (this takes a few minutes)..."
make -j"$(sysctl -n hw.ncpu)"

# Verify
echo ""
echo "=== Build complete ==="
./ffmpeg -version 2>&1 | head -5
echo ""
echo "Dynamic dependencies (should only show system libs):"
otool -L ./ffmpeg || true
echo ""
echo "TLS protocols:"
./ffmpeg -protocols 2>&1 | grep -i "tls\|rtmp" || true

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
