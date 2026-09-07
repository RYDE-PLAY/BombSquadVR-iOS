#import "BSCardboardBridge.h"

#import <GLKit/GLKit.h>
#import <string.h>
#import <time.h>

#import "cardboard.h"

namespace {

constexpr int kMatrixFloatCount = 16;

void StoreIdentity(float *matrix) {
  GLKMatrix4 identity = GLKMatrix4Identity;
  memcpy(matrix, identity.m, sizeof(float) * kMatrixFloatCount);
}

CardboardEye EyeFromInt(int eye) {
  return eye == 0 ? kLeft : kRight;
}

}  // namespace

@interface BSCardboardBridge () {
  CardboardHeadTracker *_headTracker;
  CardboardLensDistortion *_lensDistortion;
  CardboardDistortionRenderer *_distortionRenderer;
  int _displayWidth;
  int _displayHeight;
  int _deviceParamsChangedCount;
  BOOL _isUsingFallbackViewer;
  BOOL _distortionMeshDirty;
}
@end

@implementation BSCardboardBridge

- (instancetype)init {
  self = [super init];
  if (self) {
    _headTracker = CardboardHeadTracker_create();
    _deviceParamsChangedCount = -1;
  }
  return self;
}

- (void)dealloc {
  if (_distortionRenderer != nullptr) {
    CardboardDistortionRenderer_destroy(_distortionRenderer);
  }
  if (_lensDistortion != nullptr) {
    CardboardLensDistortion_destroy(_lensDistortion);
  }
  if (_headTracker != nullptr) {
    CardboardHeadTracker_destroy(_headTracker);
  }
}

- (BOOL)hasLensDistortion {
  return _lensDistortion != nullptr;
}

- (BOOL)isUsingFallbackViewer {
  return _isUsingFallbackViewer;
}

- (void)resume {
  CardboardHeadTracker_resume(_headTracker);
}

- (void)pause {
  CardboardHeadTracker_pause(_headTracker);
}

- (void)recenter {
  CardboardHeadTracker_recenter(_headTracker);
}

- (void)scanViewerQRCode {
  CardboardQrCode_scanQrCodeAndSaveDeviceParams();
}

- (void)destroyDistortionRenderer {
  if (_distortionRenderer != nullptr) {
    CardboardDistortionRenderer_destroy(_distortionRenderer);
    _distortionRenderer = nullptr;
    _distortionMeshDirty = YES;
  }
}

- (BOOL)ensureDistortionRenderer {
  if (_lensDistortion == nullptr) {
    return NO;
  }

  if (_distortionRenderer == nullptr) {
    CardboardOpenGlEsDistortionRendererConfig config = {kGlTexture2D};
    if (EAGLContext.currentContext.API == kEAGLRenderingAPIOpenGLES3) {
      _distortionRenderer =
          CardboardOpenGlEs3DistortionRenderer_create(&config);
    } else {
      _distortionRenderer =
          CardboardOpenGlEs2DistortionRenderer_create(&config);
    }
    _distortionMeshDirty = YES;
  }
  if (_distortionRenderer == nullptr) {
    return NO;
  }

  if (_distortionMeshDirty) {
    CardboardMesh leftMesh;
    CardboardMesh rightMesh;
    CardboardLensDistortion_getDistortionMesh(_lensDistortion, kLeft, &leftMesh);
    CardboardLensDistortion_getDistortionMesh(_lensDistortion, kRight, &rightMesh);
    if (leftMesh.n_indices <= 0 || rightMesh.n_indices <= 0) {
      return NO;
    }
    CardboardDistortionRenderer_setMesh(_distortionRenderer, &leftMesh, kLeft);
    CardboardDistortionRenderer_setMesh(_distortionRenderer, &rightMesh, kRight);
    _distortionMeshDirty = NO;
  }
  return YES;
}

- (BOOL)updateLensWithDisplayWidth:(int)displayWidth height:(int)displayHeight {
#if TARGET_OS_SIMULATOR
  // The Cardboard iOS SDK falls back to generic screen params for Simulator
  // model names such as "arm64"; keep simulator verification on the local LR
  // fallback projection and use full Cardboard lens params on physical devices.
  return NO;
#else
  if (displayWidth <= 0 || displayHeight <= 0) {
    return NO;
  }

  int paramsChangedCount = CardboardQrCode_getDeviceParamsChangedCount();
  if (_lensDistortion != nullptr && _displayWidth == displayWidth &&
      _displayHeight == displayHeight &&
      _deviceParamsChangedCount == paramsChangedCount) {
    return YES;
  }

  uint8_t *encodedDeviceParams = nullptr;
  int size = 0;
  BOOL usingFallback = NO;
  BOOL shouldDestroyDeviceParams = NO;
  CardboardQrCode_getSavedDeviceParams(&encodedDeviceParams, &size);
  shouldDestroyDeviceParams = encodedDeviceParams != nullptr;

  if (size == 0) {
    encodedDeviceParams = nullptr;
    CardboardQrCode_getCardboardV1DeviceParams(&encodedDeviceParams, &size);
    usingFallback = YES;
    shouldDestroyDeviceParams = NO;
  }

  if (size == 0 || encodedDeviceParams == nullptr) {
    if (shouldDestroyDeviceParams) {
      CardboardQrCode_destroy(encodedDeviceParams);
    }
    return NO;
  }

  CardboardLensDistortion *newLensDistortion =
      CardboardLensDistortion_create(encodedDeviceParams, size, displayWidth, displayHeight);
  if (shouldDestroyDeviceParams) {
    CardboardQrCode_destroy(encodedDeviceParams);
  }

  if (newLensDistortion == nullptr) {
    return NO;
  }

  if (_lensDistortion != nullptr) {
    CardboardLensDistortion_destroy(_lensDistortion);
  }
  _lensDistortion = newLensDistortion;

  _displayWidth = displayWidth;
  _displayHeight = displayHeight;
  _deviceParamsChangedCount = paramsChangedCount;
  _isUsingFallbackViewer = usingFallback;
  _distortionMeshDirty = YES;
  return YES;
#endif
}

- (void)copyHeadPosition:(float *)position
             orientation:(float *)orientation
         predictionNanos:(int64_t)predictionNanos
     viewportOrientation:(int)viewportOrientation {
  if (_headTracker == nullptr) {
    position[0] = position[1] = position[2] = 0.0f;
    orientation[0] = orientation[1] = orientation[2] = 0.0f;
    orientation[3] = 1.0f;
    return;
  }

  const int64_t timestamp =
      clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + predictionNanos;
  CardboardHeadTracker_getPose(
      _headTracker, timestamp,
      static_cast<CardboardViewportOrientation>(viewportOrientation), position,
      orientation);
}

- (void)copyProjectionForEye:(int)eye
                        near:(float)nearClip
                         far:(float)farClip
                        into:(float *)matrix {
  if (_lensDistortion == nullptr) {
    StoreIdentity(matrix);
    return;
  }
  CardboardLensDistortion_getProjectionMatrix(
      _lensDistortion, EyeFromInt(eye), nearClip, farClip, matrix);
}

- (void)copyEyeFromHeadForEye:(int)eye into:(float *)matrix {
  if (_lensDistortion == nullptr) {
    StoreIdentity(matrix);
    return;
  }
  CardboardLensDistortion_getEyeFromHeadMatrix(
      _lensDistortion, EyeFromInt(eye), matrix);
}

- (void)copyFieldOfViewForEye:(int)eye into:(float *)fieldOfView {
  if (_lensDistortion == nullptr) {
    fieldOfView[0] = fieldOfView[1] = fieldOfView[2] = fieldOfView[3] = 0.0f;
    return;
  }
  CardboardLensDistortion_getFieldOfView(
      _lensDistortion, EyeFromInt(eye), fieldOfView);
}

- (BOOL)renderDistortionWithSourceTexture:(unsigned int)sourceTexture
                         targetFramebuffer:(unsigned int)targetFramebuffer
                                     width:(int)width
                                    height:(int)height {
  if (sourceTexture == 0 || width <= 0 || height <= 0) {
    return NO;
  }
  if (![self ensureDistortionRenderer]) {
    return NO;
  }

  CardboardEyeTextureDescription leftEye;
  leftEye.texture = sourceTexture;
  leftEye.left_u = 0.0f;
  leftEye.right_u = 0.5f;
  leftEye.top_v = 1.0f;
  leftEye.bottom_v = 0.0f;

  CardboardEyeTextureDescription rightEye;
  rightEye.texture = sourceTexture;
  rightEye.left_u = 0.5f;
  rightEye.right_u = 1.0f;
  rightEye.top_v = 1.0f;
  rightEye.bottom_v = 0.0f;

  CardboardDistortionRenderer_renderEyeToDisplay(
      _distortionRenderer, targetFramebuffer, 0, 0, width, height, &leftEye,
      &rightEye);
  return YES;
}

@end
