# Third-party source and build notes

[APP-SUBMODULES.txt](APP-SUBMODULES.txt) records the source revisions vendored
in this snapshot. The app incorporates Moonlight iOS commit
[a52f344](https://github.com/moonlight-stream/moonlight-ios/commit/a52f344d0042f0b692deade1fa7747abf75de1d7)
and Moonlight Common C commit
[5a26329](https://github.com/moonlight-stream/moonlight-common-c/commit/5a2632990f5d77f6090cfb6f70797c1e16a630e0).
Both upstream commits add the App Store distribution exception. The Common C
timing change is preserved in `BuildScripts/patches/moonlight-common-visionos.patch`.

The archives retain upstream license files and notices. Run
`shasum -a 256 -c SHA256SUMS` in this directory to verify the archives.

| Component | Source |
|---|---|
| FFmpeg | [3f890fb](https://github.com/FFmpeg/FFmpeg/tree/3f890fbfd9014843c51408c8f7ab3ba4aef7d354), LGPL 2.1 or later for the linked configuration |
| Opus | [1.4](https://downloads.xiph.org/releases/opus/opus-1.4.tar.gz), see COPYING in the archive |
| SDL2 | [2.32.10](https://github.com/libsdl-org/SDL/tree/release-2.32.10), zlib license. The checked-in SDL API headers are from [2.28.5](https://github.com/libsdl-org/SDL/tree/15ead9a40d09a1eb9972215cceac2bf29c9b77f6). |
| OpenSSL | [3.3.2](https://github.com/openssl/openssl/releases/tag/openssl-3.3.2), Apache 2.0. `OpenSSL-provider/` preserves the source build recipe and Apple target configuration at [8729614](https://github.com/krzyzanowskim/OpenSSL/tree/8729614a93e6b20307db3c3359aed81f030facaa). |
| OpenSSL-Package | [b9eb055](https://github.com/krzyzanowskim/OpenSSL-Package/tree/b9eb055fdf73e595cb4b9f665d13dc85975bf80a), SwiftPM wrapper for XCFramework release 3.3.2000 |
| Swift Collections | [94cf62b](https://github.com/apple/swift-collections/tree/94cf62b3ba8d4bed62680a282d4c25f9c63c2efb), Apache 2.0 |
| Depth Anything Small and V2 Small | Apple's Apache 2.0 Core ML packages are in `Hololink/Models/`. Model cards and upstream file hashes are in `CoreML-notices/`. |

## Rebuild or replace the native libraries

The visionOS and visionOS Simulator libraries were built from the FFmpeg,
Opus and SDL sources above with Xcode 27.2 (27B52) using the recipes in
`BuildScripts/`. The SDL recipe applies `sdl2-audio-only.patch`.
Install CMake to rebuild the audio libraries.

From the repository root, run these commands to rebuild and relink.

```sh
bash BuildScripts/build-ffmpeg-visionos.sh
bash BuildScripts/build-audio-visionos.sh
UNSIGNED=1 bash BuildScripts/archive.sh
```

To use a modified FFmpeg, unpack `FFmpeg-3f890fbfd9.tar.gz`, make your
changes, and repack the directory with the original top-level name.
In `build-ffmpeg-visionos.sh`, set the source URL to a local
`file://` URL for your archive and update its SHA-256. Run the FFmpeg and
app archive commands above. The app will link against your modified copy.
The LGPL permits reverse engineering to debug these modifications.

SwiftPM verifies the OpenSSL XCFramework at SHA-256
`41d034ea1c075bfa74048e851358a550996c286de8230d1df39f137b06235c87`.
The app archive uses the arm64 visionOS slice. To build OpenSSL, use the
provider's Makefile and scripts with the included 3.3.2 source. Point the
wrapper's binary target at your replacement XCFramework.
