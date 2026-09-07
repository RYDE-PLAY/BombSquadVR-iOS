#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BombSquadVRBallisticaHost : NSObject

+ (instancetype)sharedHost;

- (void)startWithResourcePath:(NSString *)resourcePath
                    cachePath:(NSString *)cachePath
                   configPath:(NSString *)configPath;
- (BOOL)stepInitialization;
- (void)setAppActive:(BOOL)active;
- (void)suspendApp;
- (void)unsuspendApp;
- (void)setEyeWidth:(NSInteger)width height:(NSInteger)height;
- (BOOL)renderStereoFrameWithDrawableWidth:(NSInteger)drawableWidth
                                    height:(NSInteger)drawableHeight
                                   headYaw:(float)headYaw
                                 headPitch:(float)headPitch
                                  headRoll:(float)headRoll
                                   leftEye:(const float *)leftEye
                                  rightEye:(const float *)rightEye;
- (void)connectControllerWithName:(NSString *)name
                        identifier:(NSString *)identifier;
- (void)disconnectControllerWithIdentifier:(NSString *)identifier;
- (void)pushControllerAxisWithIdentifier:(NSString *)identifier
                                    axis:(NSInteger)axis
                                   value:(float)value;
- (void)pushControllerButtonWithIdentifier:(NSString *)identifier
                                    button:(NSInteger)button
                                   pressed:(BOOL)pressed;

@property(nonatomic, readonly, getter=isStarted) BOOL started;
@property(nonatomic, readonly, getter=isInitialized) BOOL initialized;
@property(nonatomic, readonly) NSString *statusText;

@end

NS_ASSUME_NONNULL_END
