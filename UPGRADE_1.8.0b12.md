# Ballistica 1.8.0b12 iOS VR migration

This branch upgrades the original iOS Cardboard integration from Ballistica
1.8.0a105/build 23002 to upstream `e55b28ad0` (1.8.0b12/build 23040).
The original checkout remains at its tested version. All migration and build
outputs live in this separate worktree.

## Changes

- Preserve the Apple stereo entry point, per-eye scissor, and GLKView drawable
  framebuffer capture while merging upstream's render-view and profiling work.
- Include stereo frames in the upstream render CPU profiling path.
- Apply the VR depth-of-field override only to the main view so new texture
  views, such as character previews, retain their authored depth-of-field settings.
- Add the six new UIKit bridge methods for device feedback, gyro capability,
  and optional overlay browsing. Cache capability values before engine startup;
  queries from the logic thread never synchronously wait for the main thread.
- Implement iPhone impact/notification feedback on the main thread. Simulator
  feedback and gyro capability return false. Head pose remains owned by the
  existing VR path; no additional engine tilt stream is started.
- Report in-app browsing as unsupported and retain the existing external URL
  opening behavior. This migration does not add an embedded browser UI.
- Pin BeeWare Python-Apple-support `3.14-b11` at
  `0fce8b7c92948cab2e556fafe6634ff8e6cb7b0e`, matching Python 3.14.7,
  OpenSSL 3.5.8, and zstd 1.5.7.
- Add the vendored zstd header path to the native engine build. Verify the
  Python merged archive contains zstd definitions used by the native engine.
- Key the adapted Plus cache by its upstream hash, SDK/platform, SDK version,
  and adaptation version so old outputs cannot silently survive an upgrade.
- Adopt the UIKit Scene lifecycle, create the window with `UIWindowScene`,
  and move rendering/audio/engine foreground callbacks into `SceneDelegate`.
  SDK 27/iOS 27 rejected the old AppDelegate-only lifecycle before engine
  initialization; the migration removes that startup trap. Keep the process-wide
  GL view alive across scene reconnection and use scene windows for dialogs.
- Regenerate `assets-ios` and stage the new builtin package
  `a-0.babuiltinassets.261007a`, Python modules, standard library, and manifest.

## Verification

Completed:

- `make env` and `make assets-ios`.
- Python 3.14.7 builds for `iphoneos.arm64` and `iphonesimulator.arm64`,
  including static `_zstd` and merged zstd symbol checks.
- Asset staging and Cardboard device static library build.
- Python script syntax checks and Git whitespace checks.

- Xcode 27/SDK 27 Debug application builds for both generic iOS device
  (unsigned) and arm64 iOS Simulator: `BUILD SUCCEEDED`.
- iPhone 17 / iOS 27 simulator startup: engine log confirms
  `BallisticaKit 1.8.0b12 build 23040`. Online asset download completed and
  the full-quality main menu renders in both eyes. Screenshot:
  `BombSquadVR/Build/UpgradeLogs/stereo-menu-verified.png`.
- Switching to Settings and returning retains the same process and resumes
  stereo rendering. This is a foreground/background smoke test; scene
  disconnection/reconnection and a gameplay session are not yet exercised.

The simulator test uses bundle identifier `com.ryde.bombsquadvr.upgrade`,
leaving the baseline installed application intact. The simulator emitted a
WebKit accessibility duplicate-class warning, locale fallback, an initial
slow audio-device warning, a redundant inactive-state warning inherited from
the host's suspend path, and a background-dynamics overload warning. No fatal
engine error was observed during this smoke test. Simulator timing is not
evidence of real-device VR frame rate.

Logs and generated outputs are under
`BombSquadVR/Build/UpgradeLogs`, `Build/UpgradeDevice`, and
`Build/UpgradeSimulator` and are excluded from Git.

## Device installation (2026-10-09)

- Signed Debug build succeeded using the existing development account.
- Installed on the connected physical iPhone 17 (iOS 27.0.1) as
  **BombSquad VR Upgrade**, bundle ID `com.ryde.bombsquadvr.upgrade`.
- Launch succeeded; device console confirms `BallisticaKit 1.8.0b12 build
  23040 starting...`, and the application process remained present during the
  initial check. Device build/install/runtime logs are in `Build/UpgradeLogs`.
- Real-device visual, sensor, controller, and gameplay checks remain for the
  hands-on test; installation/startup alone does not establish them.

## Remaining hardware verification

Verify real iPhone startup, Cardboard QR calibration, lens distortion, head
tracking/recenter, controller input, foreground/background recovery, device
haptics, and sustained thermal/frame timing behavior. A simulator cannot
establish these hardware properties. Game-session protocol is now 53; use a
matching host/client for network regression tests. The old protocol-43 VR
version is not a compatible peer for this version.

The Plus archive still uses the integration's existing platform-marker
adaptation approach; successful compilation alone does not prove its complete
runtime or online compatibility.

Engine commits and this integration branch are local until explicitly pushed.
The new submodule commit must be made available in the fork before a remote
clone can reproduce this branch's pinned checkout.
