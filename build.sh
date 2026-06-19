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

# Install dependencies via Homebrew
echo "Installing dependencies..."
brew install openssl pkg-config nasm x264

OPENSSL_DIR=$(brew --prefix openssl)
X264_DIR=$(brew --prefix x264)
echo "OpenSSL: ${OPENSSL_DIR}"
echo "x264: ${X264_DIR}"

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

# Configure — minimal build: OpenSSL + libx264 + AAC + FLV
export PKG_CONFIG_PATH="${OPENSSL_DIR}/lib/pkgconfig:${X264_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

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
  --enable-protocol=tls \
  --enable-protocol=pipe \
  --enable-protocol=file \
  --enable-static \
  --disable-shared \
  --extra-cflags="-I${OPENSSL_DIR}/include -I${X264_DIR}/include" \
  --extra-ldflags="-L${OPENSSL_DIR}/lib -L${X264_DIR}/lib" \
  --pkg-config-flags="--static"

# Build
echo "Building (this takes a few minutes)..."
make -j"$(sysctl -n hw.ncpu)"

# Verify
echo ""
echo "=== Build complete ==="
./ffmpeg -version 2>&1 | head -5
echo ""
echo "TLS protocols:"
./ffmpeg -protocols 2>&1 | grep -i "tls\|rtmp" || true
echo ""
echo "Encoders:"
./ffmpeg -encoders 2>&1 | grep -i "aac\|x264\|flv" || true

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
echo "  (next to the app binary, so ffmpeg-sidecar finds it)"
