#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BSCardboardBridge : NSObject

@property(nonatomic, readonly) BOOL hasLensDistortion;
@property(nonatomic, readonly) BOOL isUsingFallbackViewer;

- (void)resume;
- (void)pause;
- (void)recenter;
- (void)scanViewerQRCode;
- (void)destroyDistortionRenderer;
- (BOOL)updateLensWithDisplayWidth:(int)displayWidth height:(int)displayHeight;
- (void)copyHeadPosition:(float *)position
             orientation:(float *)orientation
         predictionNanos:(int64_t)predictionNanos
     viewportOrientation:(int)viewportOrientation;
- (void)copyProjectionForEye:(int)eye
                        near:(float)nearClip
                         far:(float)farClip
                        into:(float *)matrix;
- (void)copyEyeFromHeadForEye:(int)eye into:(float *)matrix;
- (void)copyFieldOfViewForEye:(int)eye into:(float *)fieldOfView;
- (BOOL)renderDistortionWithSourceTexture:(unsigned int)sourceTexture
                         targetFramebuffer:(unsigned int)targetFramebuffer
                                     width:(int)width
                                    height:(int)height;

@end

NS_ASSUME_NONNULL_END
