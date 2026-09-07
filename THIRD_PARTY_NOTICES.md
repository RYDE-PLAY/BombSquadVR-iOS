# Third-party notices (inventory)

This file is an index for the BombSquadVR-iOS integration. It is not a substitute for the
license text shipped by each dependency. Before a public release, verify the
exact revisions, include the corresponding notices in any distributable
artifact, and obtain any required permission.

| Component | How it enters the build | Notice/action |
| --- | --- | --- |
| Ballistica engine and tools | ballistica/ checkout or submodule | Preserve ballistica/LICENSE and the individual notices under ballistica/src/external/. The upstream README distinguishes MIT source from proprietary assets and prebuilt binaries. |
| Google Cardboard SDK | BombSquadVR/Scripts/bootstrap_cardboard.sh (v1.34.0, commit 4775db6e0a92fdc8bd102a818d741f2bde372876) | Keep the Cardboard Apache 2.0 license. The SDK's third_party/unity_plugin_api is under the Unity Companion License and has additional conditions; review before distributing that code. |
| Protobuf-C++ 3.18.0 | CocoaPods Podfile | CocoaPods downloads the source and license at build time. Preserve the pod's license/notice in binary distributions as required. |
| OpenAL Soft | Ballistica openal_apple_test_build pcommand | The generated checkout contains its own COPYING and dependency notices. Review the LGPL obligations before distributing a signed app. |
| Ogg/Vorbis | Hash-verified source archives downloaded by the BombSquadVR-iOS engine script | Keep the upstream BSD-style notices and the archive hashes used by the script. |
| Apple SDK/frameworks | Xcode/iOS SDK | Apple SDK terms apply; these are supplied by Xcode and are not redistributed by this repository. |

BallisticaResources/, the downloaded/adapted Ballistica Plus archive and any IPA
containing them are intentionally excluded from this public source tree. Their
use and redistribution require a separate, authorized source. Do not infer
permission from the fact that a build script can fetch an artifact.
