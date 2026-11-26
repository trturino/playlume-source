#!/bin/bash
# Rebuild native audio libraries; SDL 2.32 adds visionOS support and is ABI
# compatible with the SDL 2.28 headers used by the client.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/hololink-audio.XXXXXX")"
trap 'rm -rf "$build_root"' EXIT

curl --fail --location --silent --show-error \
    https://downloads.xiph.org/releases/opus/opus-1.4.tar.gz \
    --output "$build_root/opus.tar.gz"
curl --fail --location --silent --show-error \
    https://github.com/libsdl-org/SDL/archive/refs/tags/release-2.32.10.tar.gz \
    --output "$build_root/sdl.tar.gz"
echo "c9b32b4253be5ae63d1ff16eea06b94b5f0f2951b7a02aceef58e3a3ce49c51f  $build_root/opus.tar.gz" | shasum -a 256 --check
echo "03f9d7c191a837525c9cda6406af2f2e48be02b5e7eb03d949cc9f1e9ca41c8b  $build_root/sdl.tar.gz" | shasum -a 256 --check
tar -xzf "$build_root/opus.tar.gz" -C "$build_root"
tar -xzf "$build_root/sdl.tar.gz" -C "$build_root"
# SDL's tablet helper otherwise references its disabled UIKit video backend.
patch -d "$build_root/SDL-release-2.32.10" -p1 < "$repo_root/BuildScripts/patches/sdl2-audio-only.patch"

for sdk in xros xrsimulator; do
    if [[ "$sdk" == xros ]]; then
        platform=visionOS
    else
        platform=visionOS-Sim
    fi
    cmake_args=(
        -DCMAKE_SYSTEM_NAME=visionOS -DCMAKE_OSX_SYSROOT="$sdk"
        -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=2.0
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        -DBUILD_SHARED_LIBS=OFF
    )
    cmake -S "$build_root/opus-1.4" -B "$build_root/opus-$sdk" \
        "${cmake_args[@]}" -DOPUS_BUILD_TESTING=OFF
    cmake --build "$build_root/opus-$sdk" --parallel "$(sysctl -n hw.logicalcpu)"
    cmake -S "$build_root/SDL-release-2.32.10" -B "$build_root/sdl-$sdk" \
        "${cmake_args[@]}" -DSDL_SHARED=OFF -DSDL_STATIC=ON \
        -DSDL_TEST=OFF -DSDL_TESTS=OFF -DSDL_VIDEO=OFF -DSDL_RENDER=OFF \
        -DSDL_JOYSTICK=OFF -DSDL_HAPTIC=OFF -DSDL_SENSOR=OFF \
        -DSDL_HIDAPI=OFF -DSDL_POWER=OFF -DSDL_MISC=OFF
    cmake --build "$build_root/sdl-$sdk" --target SDL2-static --parallel "$(sysctl -n hw.logicalcpu)"
    mkdir -p "$repo_root/libs/opus/lib/$platform" "$repo_root/libs/SDL2/lib/$platform"
    cp "$build_root/opus-$sdk/libopus.a" "$repo_root/libs/opus/lib/$platform/"
    cp "$build_root/sdl-$sdk/libSDL2.a" "$repo_root/libs/SDL2/lib/$platform/"
done
