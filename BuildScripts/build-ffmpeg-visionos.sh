#!/bin/bash
# Build the FFmpeg revision matching the checked-in public and private headers.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/hololink-ffmpeg.XXXXXX")"
trap 'rm -rf "$build_root"' EXIT

curl --fail --location --silent --show-error \
    https://github.com/FFmpeg/FFmpeg/archive/3f890fbfd9.tar.gz \
    --output "$build_root/source.tar.gz"
echo "4e30c1ffa93b7bfe329032877d969d4811a5ac4c872125d334262f5158048899  $build_root/source.tar.gz" | shasum -a 256 --check
tar -xzf "$build_root/source.tar.gz" -C "$build_root"
source_dir="$build_root/FFmpeg-3f890fbfd9014843c51408c8f7ab3ba4aef7d354"

for sdk in xros xrsimulator; do
    if [[ "$sdk" == xros ]]; then
        platform=visionOS
        target=arm64-apple-xros2.0
    else
        platform=visionOS-Sim
        target=arm64-apple-xros2.0-simulator
    fi
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    mkdir -p "$build_root/$sdk"
    cd "$build_root/$sdk"
    "$source_dir/configure" \
        --prefix="$build_root/install-$sdk" \
        --cc="$(xcrun --sdk "$sdk" --find clang)" \
        --extra-cflags="-target $target -isysroot $sdk_path" \
        --extra-ldflags="-target $target -isysroot $sdk_path" \
        --arch=arm64 --target-os=darwin --enable-cross-compile \
        --disable-all --disable-autodetect --disable-x86asm --disable-debug \
        --enable-pic --enable-avcodec --enable-avformat \
        --enable-muxer=flv --enable-decoder=av1
    make -j "$(sysctl -n hw.logicalcpu)"
    mkdir -p "$repo_root/libs/FFmpeg/lib/$platform"
    for library in avcodec avformat avutil; do
        cp "lib$library/lib$library.a" "$repo_root/libs/FFmpeg/lib/$platform/"
    done
done
