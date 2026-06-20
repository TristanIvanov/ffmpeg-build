#!/bin/bash
# Build FFmpeg with OpenSSL for macOS (local build script)
# Usage: ./build.sh [ffmpeg_version]
set -euo pipefail

FFMPEG_VERSION="${1:-8.1.2}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_DIR="${SCRIPT_DIR}/output"

echo "=== Building FFmpeg ${FFMPEG_VERSION} with OpenSSL (fully static) ==="

brew install pkg-config nasm
OPENSSL_TARGET=$(uname -m | sed 's/arm64/darwin64-arm64/;s/x86_64/darwin64-x86_64/')
echo "OpenSSL target: ${OPENSSL_TARGET}"

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Build OpenSSL from source (static only)
if [ ! -d "openssl-static" ]; then
  echo "Building OpenSSL from source..."
  curl -L "https://github.com/openssl/openssl/releases/download/openssl-3.4.1/openssl-3.4.1.tar.gz" -o openssl.tar.gz
  tar xf openssl.tar.gz
  cd openssl-3.4.1
  ./Configure "${OPENSSL_TARGET}" no-shared no-dso no-tests --prefix="${BUILD_DIR}/openssl-static"
  make -j"$(sysctl -n hw.ncpu)"
  make install_sw
  cd ..
fi
OPENSSL_STATIC="${BUILD_DIR}/openssl-static"

# Build x264 from source (static, no X11)
if [ ! -d "x264" ]; then
  echo "Building x264 from source..."
  PKG_CONFIG_LIBDIR=/dev/null git clone --depth 1 https://code.videolan.org/videolan/x264.git
  cd x264
  PKG_CONFIG_LIBDIR=/dev/null ./configure --enable-static --disable-shared --disable-opencl --disable-cli
  make -j"$(sysctl -n hw.ncpu)"
  sudo make install
  cd ..
fi

# Download FFmpeg source
if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
  echo "Downloading FFmpeg ${FFMPEG_VERSION}..."
  curl -L "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o ffmpeg.tar.xz
  tar xf ffmpeg.tar.xz
  rm ffmpeg.tar.xz
fi

cd "ffmpeg-${FFMPEG_VERSION}"

PKG_CONFIG_LIBDIR=/dev/null PKG_CONFIG_PATH=/dev/null ./configure \
  --enable-openssl \
  --enable-nonfree \
  --enable-gpl \
  --enable-libx264 \
  --disable-doc --disable-ffplay --disable-ffprobe \
  --disable-encoders --enable-encoder=aac --enable-encoder=libx264 --enable-encoder=flv \
  --disable-decoders --enable-decoder=aac --enable-decoder=h264 --enable-decoder=pcm_s16le --enable-decoder=pcm_s32le --enable-decoder=mp3 \
  --disable-muxers --enable-muxer=flv \
  --disable-demuxers --enable-demuxer=pcm_s16le --enable-demuxer=pcm_s32le --enable-demuxer=wav --enable-demuxer=mp3 --enable-demuxer=image2 \
  --disable-protocols --enable-protocol=rtmp --enable-protocol=rtmps --enable-protocol=tcp --enable-protocol=udp --enable-protocol=tls --enable-protocol=https --enable-protocol=http --enable-protocol=pipe --enable-protocol=file \
  --enable-static --disable-shared \
  --extra-cflags="-I${OPENSSL_STATIC}/include" \
  --extra-ldflags="-L${OPENSSL_STATIC}/lib"

echo "Building..."
make -j"$(sysctl -n hw.ncpu)"

# Verify
echo "=== Checking dynamic dependencies ==="
otool -L ./ffmpeg
if otool -L ./ffmpeg | grep -i "libxcb\|libx11\|/opt/homebrew\|/usr/local/opt"; then
  echo "ERROR: Forbidden dynamic dependencies found!"
  exit 1
fi
echo "Verification passed!"
./ffmpeg -version 2>&1 | head -5
./ffmpeg -protocols 2>&1 | grep -i "tls\|rtmp" || true

# Package
mkdir -p "${OUTPUT_DIR}"
cp ffmpeg "${OUTPUT_DIR}/ffmpeg"
chmod +x "${OUTPUT_DIR}/ffmpeg"
ARCH=$(uname -m)
cd "${OUTPUT_DIR}"
zip "ffmpeg-${FFMPEG_VERSION}-macos-${ARCH}.zip" ffmpeg
echo "Output: ${OUTPUT_DIR}/ffmpeg-${FFMPEG_VERSION}-macos-${ARCH}.zip"
