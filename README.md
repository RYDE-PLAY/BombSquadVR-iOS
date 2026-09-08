# BombSquadVR-iOS

Unofficial online iOS Cardboard VR integration based on the Ballistica engine.
This repository contains the integration code and build scripts.

BallisticaResources/, the Ballistica Plus library and IPA files are not
included. Developers must generate or obtain those inputs themselves and must
have permission to use them. This project is not an official BombSquad,
Ballistica, Google Cardboard or Apple product.

## Repository layout

~~~text
BombSquadVR/          iOS app, bridge and build scripts
ballistica/           Ballistica dependency (submodule at a pinned commit)
BallisticaResources/  local generated resources (not committed)
~~~

## 1. Clone

Clone the project repository. The command creates a local directory named
`BombSquadVR-iOS`; you do not need to create a GitHub repository of your own.

~~~sh
git clone --recurse-submodules https://github.com/RYDE-PLAY/BombSquadVR-iOS.git
cd BombSquadVR-iOS
git submodule update --init --recursive
~~~

## 2. Install prerequisites

Install [Xcode](https://developer-mdn.apple.com/download/applications/) with the iOS 16 SDK and accept its license. Then install the
command-line tools and build dependencies:

~~~sh
xcode-select --install
brew install rsync clang-format python@3.14 uv xcodegen cocoapods
~~~

Required tools: Python 3.14, uv, XcodeGen 2.45.0+, CocoaPods, make, rsync and
the Apple xcrun toolchain.

## 3. Prepare the engine and local resources

Run from the BombSquadVR-iOS repository root:

~~~sh
cd ballistica
make env
tools/pcommand python_build_apple iphonesimulator.arm64
tools/pcommand python_build_apple iphoneos.arm64
make assets-ios

cd ../BombSquadVR
./Scripts/sync_ballistica_assets.sh
./Scripts/bootstrap_cardboard.sh
xcodegen generate
~~~

make assets-ios may need network access to Ballistica services. The sync
script only stages its generated outputs into ../BallisticaResources; it does
not download or authorize resources. See
[BallisticaResources/README.md](BallisticaResources/README.md) for the exact
layout.

If tools/pcommand is missing, run make env again from ballistica.

## 4. Build for the simulator

~~~sh
cd BombSquadVR
xcodebuild \
  -project BombSquadVR.xcodeproj \
  -scheme BombSquadVR \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath Build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
~~~

## 5. Build and run on an iPhone

Use your own Apple Team and a unique Bundle ID. Do not commit certificates,
private keys or provisioning profiles.

Before running the commands:

- `DEVICE_UDID`: connect and trust the iPhone, then copy its Identifier from
  `xcrun devicectl list devices` or Xcode's **Window > Devices and Simulators**.
- `TEAM_ID`: add your Apple ID in **Xcode > Settings > Accounts**, select your
  Team, and copy its Team ID. Enable **Automatically manage signing** for the target.
- `BUNDLE_ID`: choose a unique reverse-DNS-style identifier such as
  `com.yourname.bombsquadvr.ios`; do not reuse the official app's identifier.

~~~sh
cd BombSquadVR

DEVICE_UDID="YOUR_DEVICE_UDID"
TEAM_ID="YOUR_TEAM_ID"
BUNDLE_ID="com.example.bombsquadvr.ios"

xcodebuild \
  -project BombSquadVR.xcodeproj \
  -scheme BombSquadVR \
  -configuration Debug \
  -sdk iphoneos \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath Build/DeviceDerivedData \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  build

APP=Build/DeviceDerivedData/Build/Products/Debug-iphoneos/BombSquadVR.app
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
xcrun devicectl device process launch \
  --device "$DEVICE_UDID" \
  --terminate-existing \
  "$BUNDLE_ID"
~~~

If iOS blocks the first launch, trust the developer app in Settings.

## Licensing

Keep the upstream licenses and notices. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before distributing code or
an app. Never commit BallisticaResources/, downloaded Plus binaries,
generated build output or signing material.

For Ballistica-wide build information, see the
[README at the pinned Ballistica fork commit](https://github.com/RYDE-PLAY/ballistica/blob/2ff3b4a190ef338c4cd4cdfd6c182866ffb285a1/README.md).
