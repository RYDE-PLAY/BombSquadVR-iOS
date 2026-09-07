// Local iOS/Cardboard VR build configuration for the isolated BombSquadVR app.

#ifndef BOMBSQUADVR_BALLISTICABRIDGE_BALLISTICABUILDCONFIGIOS_H_
#define BOMBSQUADVR_BALLISTICABRIDGE_BALLISTICABUILDCONFIGIOS_H_

#define BA_PLATFORM "ios"
#define BA_PLATFORM_IOS 1
#define BA_PLATFORM_IOS_TVOS 1

#define BA_ARCH "arm64"

#define BA_VARIANT "cardboard"
#define BA_VARIANT_CARDBOARD 1

#define BA_XCODE_BUILD 1
#define BA_MONOLITHIC_BUILD 1
#define BA_DEFINE_MAIN 0
#define BA_MINSDL_BUILD 1
#define BA_CONTAINS_PYTHON_DIST 1
#define BA_ENABLE_AUDIO 1
#define BA_ENABLE_OPENGL 1
#define BA_OPENGL_IS_ES 1
#define BA_USE_FRAMEWORK_OPENAL 1
#define BA_USE_TREMOR_VORBIS 0
#define BA_VR_BUILD 1
#define GLES_SILENCE_DEPRECATION 1

// All monolithic objects crossing the app/static-library boundary must use
// one Object layout. The private Plus archive and the native build script are
// release-layout builds even when the Xcode wrapper target is Debug.
#define BA_DEBUG_BUILD 0
#ifndef NDEBUG
#define NDEBUG
#endif

#define dTRIMESH_ENABLED 1

#include "ballistica/shared/buildconfig/buildconfig_common.h"

#endif  // BOMBSQUADVR_BALLISTICABRIDGE_BALLISTICABUILDCONFIGIOS_H_
