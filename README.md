# Playlume source

Playlume streams PC games to Apple Vision Pro from a compatible PC running
Sunshine on the same local network. This repository provides the source for
Playlume 1.0. The app revision is recorded in [APP-REVISION](APP-REVISION).

Playlume is derived from [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios)
and uses [Moonlight Common C](https://github.com/moonlight-stream/moonlight-common-c).
Playlume adds a visionOS interface, optional on-device stereo depth, and
visionOS audio, input and video rendering.

Playlume is distributed under the [GNU GPL version 3](LICENSE.txt).
Moonlight's App Store distribution exception is included with the upstream
licenses. See [third-party source and build notes](ThirdParty/README.md) and
[license notices shipped in the app](Hololink/OpenSourceNotices.txt).

## Build for visionOS

Install Xcode with the visionOS SDK on an Apple Silicon Mac. The deployment
target is visionOS 26.0. The Xcode project is `Moonlight.xcodeproj` and its
shared scheme is `Moonlight Vision`.

```sh
bash BuildScripts/test.sh
UNSIGNED=1 bash BuildScripts/archive.sh
```

The archive is written to `Build/Hololink.xcarchive`. SwiftPM resolves the
packages in the project's `Package.resolved` file. Select your own signing
team in Xcode to install a development build on a device.

See [third-party build notes](ThirdParty/README.md#rebuild-or-replace-the-native-libraries)
to rebuild the libraries or relink Playlume against a modified FFmpeg.
