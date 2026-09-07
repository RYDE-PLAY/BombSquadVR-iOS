#import "BombSquadVRBallisticaHost.h"

#include "BallisticaBuildConfigIOS.h"

#import <CoreGraphics/CoreGraphics.h>
#import <Network/Network.h>
#import <TargetConditionals.h>
#import <UIKit/UIKit.h>

#include <algorithm>
#include <cmath>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "ballistica/base/app_adapter/app_adapter_apple.h"
#include "ballistica/base/app_platform/app_platform.h"
#include "ballistica/base/base.h"
#include "ballistica/base/graphics/graphics.h"
#include "ballistica/base/graphics/graphics_server.h"
#include "ballistica/base/input/device/joystick_input.h"
#include "ballistica/base/input/input.h"
#include "ballistica/base/logic/logic.h"
#include "ballistica/core/platform/apple/platform_apple.h"
#include "ballistica/core/platform/platform.h"
#include "ballistica/core/support/core_config.h"
#include "ballistica/shared/ballistica.h"
#include "ballistica/shared/foundation/event_loop.h"
#include "ballistica/shared/foundation/input_types.h"
#include "ballistica/shared/generic/runnable.h"
#include "ballistica/base/app_platform/apple/uikit_pasteboard.h"

#include <BallisticaKit-Swift.h>

namespace {

std::string g_resources_path;
std::string g_cache_path;
std::string g_config_path;
std::string g_os_version{"iOS"};
std::string g_locale{"en"};
std::string g_locale_tag{"en-US"};
std::string g_device_name{"iPhone"};
std::string g_device_uuid{"local-ios-vr-device"};
nw_path_monitor_t g_network_path_monitor;
dispatch_queue_t g_network_path_monitor_queue;

auto StringFromNSString(NSString* string) -> std::string {
  if (string == nil) {
    return {};
  }
  const char* utf8 = [string UTF8String];
  return utf8 == nullptr ? std::string{} : std::string{utf8};
}

auto NSStringFromString(const std::string& string) -> NSString* {
  return [[NSString alloc] initWithBytes:string.data()
                                  length:string.size()
                                encoding:NSUTF8StringEncoding] ?: @"";
}

void EnsureDirectory(NSString* path) {
  if (path.length == 0) {
    return;
  }
  [[NSFileManager defaultManager] createDirectoryAtPath:path
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
}

auto TextFont(CGFloat scale) -> UIFont* {
  return [UIFont systemFontOfSize:26.0 * scale weight:UIFontWeightMedium];
}

auto PresentingViewController() -> UIViewController* {
  UIWindow* window = nil;
  for (UIWindow* candidate in UIApplication.sharedApplication.windows) {
    if (candidate.isKeyWindow) {
      window = candidate;
      break;
    }
    if (window == nil && !candidate.isHidden && candidate.alpha > 0.0) {
      window = candidate;
    }
  }
  if (window == nil) {
    return nil;
  }

  UIViewController* controller = window.rootViewController;
  while (controller.presentedViewController != nil) {
    controller = controller.presentedViewController;
  }
  return controller;
}

auto EyeParamsFromArray(const float* values, int eye, int viewport_x,
                        int viewport_y, int viewport_width,
                        int viewport_height, float yaw, float pitch,
                        float roll)
    -> ballistica::base::GraphicsServer::VREyeRenderParams {
  ballistica::base::GraphicsServer::VREyeRenderParams params;
  params.eye = eye;
  params.yaw = yaw;
  params.pitch = pitch;
  params.roll = roll;
  params.tan_l = values[0];
  params.tan_r = values[1];
  params.tan_b = values[2];
  params.tan_t = values[3];
  params.eye_x = values[4];
  params.eye_y = values[5];
  params.eye_z = values[6];
  params.viewport_x = viewport_x;
  params.viewport_y = viewport_y;
  params.viewport_width = viewport_width;
  params.viewport_height = viewport_height;
  return params;
}

}  // namespace

namespace BallisticaKit {

auto TextTextureData::init(int width, int height,
                           const std::vector<std::string>& strings,
                           const std::vector<float>& positions,
                           const std::vector<float>& widths, float scale)
    -> TextTextureData {
  (void)widths;
  if (width <= 0 || height <= 0) {
    return TextTextureData(std::vector<std::uint8_t>(4));
  }

  CGSize size = CGSizeMake(width, height);
  UIGraphicsImageRendererFormat* format =
      [UIGraphicsImageRendererFormat preferredFormat];
  format.opaque = NO;
  format.scale = 1.0;
  UIGraphicsImageRenderer* renderer =
      [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
  UIImage* image = [renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
    (void)context;
    UIFont* font = TextFont(scale);
    NSDictionary<NSAttributedStringKey, id>* attrs = @{
      NSFontAttributeName : font,
      NSForegroundColorAttributeName : UIColor.whiteColor
    };
    for (size_t i = 0; i < strings.size(); ++i) {
      NSString* text = NSStringFromString(strings[i]);
      CGFloat x = positions[i * 2];
      CGFloat baseline = positions[i * 2 + 1];
      CGFloat y = baseline - font.ascender;
      [text drawAtPoint:CGPointMake(x, y) withAttributes:attrs];
    }
  }];

  std::vector<std::uint8_t> pixels(static_cast<size_t>(width) * height * 4);
  CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
  CGContextRef bitmap = CGBitmapContextCreate(
      pixels.data(), width, height, 8, width * 4, color_space,
      kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  if (bitmap != nullptr) {
    CGContextClearRect(bitmap, CGRectMake(0, 0, width, height));
    CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), image.CGImage);
    CGContextRelease(bitmap);
  }
  CGColorSpaceRelease(color_space);
  return TextTextureData(std::move(pixels));
}

auto TextTextureData::getTextBoundsAndWidth(const std::string& text)
    -> FloatArray5 {
  UIFont* font = TextFont(1.0);
  NSString* ns_text = NSStringFromString(text);
  NSDictionary<NSAttributedStringKey, id>* attrs = @{NSFontAttributeName : font};
  CGSize size = [ns_text sizeWithAttributes:attrs];
  float width = static_cast<float>(std::ceil(size.width));
  float top = static_cast<float>(std::ceil(font.ascender));
  float bottom = static_cast<float>(std::floor(font.descender));
  return FloatArray5(0.0f, width, bottom, top, width);
}

void FromCpp::pushRawRunnableToMain(ballistica::Runnable* runnable) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (runnable != nullptr) {
      runnable->RunAndLogErrors();
      delete runnable;
    }
  });
}

auto FromCpp::getOSVersion() -> const char* { return g_os_version.c_str(); }

auto FromCpp::getApplicationSupportDirectoryPath() -> const char* {
  return g_config_path.c_str();
}

auto FromCpp::getCacheDirectoryPath() -> const char* {
  return g_cache_path.c_str();
}

auto FromCpp::getResourcesPath() -> const char* {
  return g_resources_path.c_str();
}

auto FromCpp::getBaLocale() -> const char* { return g_locale.c_str(); }

auto FromCpp::getLocaleTag() -> const char* { return g_locale_tag.c_str(); }

void FromCpp::startNetAvailabilityMonitoring() {
  static dispatch_once_t once_token;
  dispatch_once(&once_token, ^{
    g_network_path_monitor = nw_path_monitor_create();
    g_network_path_monitor_queue = dispatch_queue_create(
        "com.froemling.bombsquad.vr.network-path", DISPATCH_QUEUE_SERIAL);
    nw_path_monitor_set_queue(g_network_path_monitor,
                              g_network_path_monitor_queue);
    nw_path_monitor_set_update_handler(
        g_network_path_monitor, ^(nw_path_t path) {
          bool available =
              nw_path_get_status(path) == nw_path_status_satisfied;
          ballistica::core::PlatformApple::OnNetAvailChanged(available);
        });
    nw_path_monitor_start(g_network_path_monitor);
  });
}

auto UIKitFromCpp::getDeviceName() -> const char* {
  return g_device_name.c_str();
}

auto UIKitFromCpp::getLegacyDeviceUUID() -> const char* {
  return g_device_uuid.c_str();
}

auto UIKitFromCpp::isTablet() -> bool {
  return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
}

void UIKitFromCpp::openURL(const std::string& url) {
  NSString* value = NSStringFromString(url);
  NSURL* ns_url = [NSURL URLWithString:value];
  if (ns_url != nil) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [UIApplication.sharedApplication openURL:ns_url
                                       options:@{}
                             completionHandler:nil];
    });
  }
}

void PushStringEditorResult(std::optional<std::string> value, bool submit) {
  if (ballistica::base::g_base == nullptr
      || ballistica::base::g_base->logic == nullptr) {
    return;
  }
  ballistica::base::g_base->logic->event_loop()->PushCall(
      [value = std::move(value), submit] {
        if (ballistica::base::g_base == nullptr
            || ballistica::base::g_base->platform == nullptr) {
          return;
        }
        if (value.has_value()) {
          ballistica::base::g_base->platform->StringEditorApply(*value, submit);
        } else {
          ballistica::base::g_base->platform->StringEditorCancel();
        }
      });
}

void UIKitFromCpp::invokeStringEditor(const std::string& title,
                                      const std::string& value, int max_chars,
                                      bool is_password,
                                      const std::string& kind) {
  NSString* ns_title = NSStringFromString(title);
  NSString* ns_value = NSStringFromString(value);
  NSString* ns_kind = NSStringFromString(kind);
  dispatch_async(dispatch_get_main_queue(), ^{
    UIViewController* presenter = PresentingViewController();
    if (presenter == nil) {
      PushStringEditorResult(std::nullopt, false);
      return;
    }

    UIAlertController* alert =
        [UIAlertController alertControllerWithTitle:ns_title
                                             message:nil
                                      preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField* text_field) {
      text_field.text = ns_value;
      text_field.secureTextEntry = is_password;
      text_field.autocorrectionType = UITextAutocorrectionTypeNo;
      text_field.autocapitalizationType = UITextAutocapitalizationTypeNone;
      if ([ns_kind isEqualToString:@"chat"]) {
        text_field.returnKeyType = UIReturnKeySend;
      }
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                               style:UIAlertActionStyleCancel
                                             handler:^(UIAlertAction*) {
                                               PushStringEditorResult(
                                                   std::nullopt, false);
                                             }]];
    NSString* action_title = [ns_kind isEqualToString:@"chat"] ? @"Send" : @"Done";
    [alert addAction:[UIAlertAction actionWithTitle:action_title
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction*) {
                                               NSString* entered =
                                                   alert.textFields.firstObject.text ?: @"";
                                               if (max_chars >= 0
                                                   && entered.length > max_chars) {
                                                 entered = [entered substringToIndex:max_chars];
                                               }
                                               PushStringEditorResult(
                                                   StringFromNSString(entered), true);
                                             }]];
    [presenter presentViewController:alert animated:YES completion:nil];
  });
}

}  // namespace BallisticaKit

namespace ballistica::base {

auto UIKitPasteboardHasText() -> bool {
  __block BOOL result = NO;
  void (^read_block)(void) = ^{
    result = UIPasteboard.generalPasteboard.hasStrings;
  };
  if (NSThread.isMainThread) {
    read_block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), read_block);
  }
  return result;
}

void UIKitPasteboardSetText(const std::string& text) {
  NSString* value = NSStringFromString(text);
  dispatch_async(dispatch_get_main_queue(), ^{
    UIPasteboard.generalPasteboard.string = value;
  });
}

void UIKitPasteboardGetTextAsync(
    std::function<void(std::optional<std::string>)> completion) {
  auto callback = std::make_shared<
      std::function<void(std::optional<std::string>)>>(std::move(completion));
  dispatch_async(dispatch_get_main_queue(), ^{
    NSString* value = UIPasteboard.generalPasteboard.string;
    if (value == nil) {
      (*callback)(std::nullopt);
    } else {
      (*callback)(StringFromNSString(value));
    }
  });
}

}  // namespace ballistica::base

@interface BombSquadVRBallisticaHost ()
@property(nonatomic, readwrite, getter=isStarted) BOOL started;
@property(nonatomic, readwrite, getter=isInitialized) BOOL initialized;
@property(nonatomic, readwrite) NSString* statusText;
@end

@implementation BombSquadVRBallisticaHost {
  std::unique_ptr<ballistica::core::CoreConfig> _coreConfig;
  std::unordered_map<std::string, ballistica::base::JoystickInput*> _controllers;
  NSInteger _lastEyeWidth;
  NSInteger _lastEyeHeight;
  BOOL _appSuspended;
}

+ (instancetype)sharedHost {
  static BombSquadVRBallisticaHost* host;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    host = [[BombSquadVRBallisticaHost alloc] init];
  });
  return host;
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _statusText = @"Waiting to start";
  }
  return self;
}

- (void)startWithResourcePath:(NSString*)resourcePath
                    cachePath:(NSString*)cachePath
                   configPath:(NSString*)configPath {
  if (self.started) {
    return;
  }

  EnsureDirectory(cachePath);
  EnsureDirectory(configPath);

  g_resources_path = StringFromNSString(resourcePath);
  g_cache_path = StringFromNSString(cachePath);
  g_config_path = StringFromNSString(configPath);
  g_os_version = StringFromNSString(UIDevice.currentDevice.systemVersion);
  g_device_name = StringFromNSString(UIDevice.currentDevice.name);
  g_locale_tag = StringFromNSString(NSLocale.currentLocale.localeIdentifier);
  g_locale = StringFromNSString(NSLocale.preferredLanguages.firstObject ?: @"en");
  g_device_uuid = StringFromNSString(
      UIDevice.currentDevice.identifierForVendor.UUIDString ?: @"local-ios-vr-device");

  int argc = 1;
  char arg0[] = "BombSquadVR";
  char* argv[] = {arg0};
  auto launch_time = ballistica::core::Platform::TimeSinceEpochSeconds();
  _coreConfig = std::make_unique<ballistica::core::CoreConfig>(
      ballistica::core::CoreConfig::ForArgsAndEnvVars(argc, argv, launch_time));
  _coreConfig->data_dir = g_resources_path;
  _coreConfig->cache_dir = g_cache_path;
  _coreConfig->config_dir = g_config_path;
  _coreConfig->dont_write_bytecode = true;
  _coreConfig->vr_mode = true;

  self.started = YES;
  self.statusText = @"Starting Ballistica VR";
}

- (BOOL)stepInitialization {
  if (!self.started || self.initialized || !_coreConfig) {
    return self.initialized;
  }
  self.initialized = ballistica::MonolithicMainIncremental(_coreConfig.get());
  self.statusText = self.initialized ? @"Ballistica VR running" : @"Loading Ballistica VR";
  return self.initialized;
}

- (void)setAppActive:(BOOL)active {
  if (self.initialized && ballistica::base::g_base != nullptr) {
    ballistica::base::g_base->SetAppActive(active);
  }
}

- (void)suspendApp {
  if (!self.initialized || _appSuspended ||
      ballistica::base::g_base == nullptr) {
    return;
  }
  ballistica::base::g_base->SetAppActive(false);
  ballistica::base::g_base->SuspendApp();
  _appSuspended = YES;
}

- (void)unsuspendApp {
  if (!self.initialized || !_appSuspended ||
      ballistica::base::g_base == nullptr) {
    return;
  }
  ballistica::base::g_base->UnsuspendApp();
  _appSuspended = NO;
}

- (void)setEyeWidth:(NSInteger)width height:(NSInteger)height {
  if (!self.initialized || width <= 0 || height <= 0) {
    return;
  }
  if (_lastEyeWidth == width && _lastEyeHeight == height) {
    return;
  }
  _lastEyeWidth = width;
  _lastEyeHeight = height;

  if (ballistica::base::g_base != nullptr &&
      ballistica::base::g_base->logic != nullptr) {
    int w = static_cast<int>(width);
    int h = static_cast<int>(height);
    ballistica::base::g_base->logic->event_loop()->PushCall([w, h] {
      if (ballistica::base::g_base != nullptr &&
          ballistica::base::g_base->graphics != nullptr) {
        ballistica::base::g_base->graphics->SetScreenResolution(
            static_cast<float>(w), static_cast<float>(h));
      }
    });
    if (ballistica::base::g_base->app_adapter != nullptr) {
      auto* adapter =
          ballistica::base::AppAdapterApple::Get(ballistica::base::g_base);
      adapter->EnableResizeFriendlyMode(w, h);
    }
  }
}

- (BOOL)renderStereoFrameWithDrawableWidth:(NSInteger)drawableWidth
                                    height:(NSInteger)drawableHeight
                                   headYaw:(float)headYaw
                                 headPitch:(float)headPitch
                                  headRoll:(float)headRoll
                                   leftEye:(const float*)leftEye
                                  rightEye:(const float*)rightEye {
  if (!self.initialized || ballistica::base::g_base == nullptr ||
      ballistica::base::g_base->app_adapter == nullptr ||
      leftEye == nullptr || rightEye == nullptr) {
    return NO;
  }

  int eye_width = static_cast<int>(drawableWidth / 2);
  int eye_height = static_cast<int>(drawableHeight);
  if (eye_width <= 0 || eye_height <= 0) {
    return NO;
  }
  [self setEyeWidth:eye_width height:eye_height];

  auto left = EyeParamsFromArray(leftEye, 0, 0, 0, eye_width, eye_height,
                                 headYaw, headPitch, headRoll);
  auto right = EyeParamsFromArray(rightEye, 1, eye_width, 0, eye_width,
                                  eye_height, headYaw, headPitch, headRoll);

  auto* adapter = ballistica::base::AppAdapterApple::Get(ballistica::base::g_base);
  return adapter->TryRenderVRStereo(0.0f, 0.0f, 0.0f, headYaw, headPitch,
                                    headRoll, left, right);
}

- (void)connectControllerWithName:(NSString*)name
                        identifier:(NSString*)identifier {
  if (!self.initialized || ballistica::base::g_base == nullptr ||
      ballistica::base::g_base->input == nullptr ||
      identifier.length == 0) {
    return;
  }

  std::string controller_id = StringFromNSString(identifier);
  if (_controllers.find(controller_id) != _controllers.end()) {
    return;
  }

  std::string controller_name = StringFromNSString(name);
  if (controller_name.empty()) {
    controller_name = "iOS Controller";
  }

  auto* joystick = ballistica::Object::NewDeferred<ballistica::base::JoystickInput>(
      -1, controller_name, true, true);
  joystick->set_is_mfi_controller(true);
  joystick->SetStandardExtendedButtons();
  joystick->SetButtonName(0, "A");
  joystick->SetButtonName(1, "X");
  joystick->SetButtonName(2, "B");
  joystick->SetButtonName(3, "Y");
  joystick->SetButtonName(4, "Menu");
  joystick->SetButtonName(5, "Left Shoulder");
  joystick->SetButtonName(6, "Right Shoulder");
  joystick->set_custom_default_player_name(controller_name);

  _controllers[controller_id] = joystick;
  ballistica::base::g_base->input->PushAddInputDeviceCall(joystick, true);
}

- (void)disconnectControllerWithIdentifier:(NSString*)identifier {
  if (!self.initialized || ballistica::base::g_base == nullptr ||
      ballistica::base::g_base->input == nullptr ||
      identifier.length == 0) {
    return;
  }

  std::string controller_id = StringFromNSString(identifier);
  auto i = _controllers.find(controller_id);
  if (i == _controllers.end()) {
    return;
  }

  ballistica::base::g_base->input->PushRemoveInputDeviceCall(i->second, true);
  _controllers.erase(i);
}

- (void)pushControllerAxisWithIdentifier:(NSString*)identifier
                                    axis:(NSInteger)axis
                                   value:(float)value {
  if (!self.initialized || ballistica::base::g_base == nullptr ||
      ballistica::base::g_base->input == nullptr ||
      identifier.length == 0 || axis < 0 || axis > 255) {
    return;
  }

  std::string controller_id = StringFromNSString(identifier);
  auto i = _controllers.find(controller_id);
  if (i == _controllers.end()) {
    return;
  }

  BAEvent event{};
  event.type = BA_JOYAXISMOTION;
  event.jaxis.axis = static_cast<uint8_t>(axis);
  event.jaxis.value = static_cast<int>(
      std::clamp(value, -1.0f, 1.0f) * 32767.0f);
  ballistica::base::g_base->input->PushJoystickEvent(event, i->second);
}

- (void)pushControllerButtonWithIdentifier:(NSString*)identifier
                                    button:(NSInteger)button
                                   pressed:(BOOL)pressed {
  if (!self.initialized || ballistica::base::g_base == nullptr ||
      ballistica::base::g_base->input == nullptr ||
      identifier.length == 0 || button < 0 || button > 255) {
    return;
  }

  std::string controller_id = StringFromNSString(identifier);
  auto i = _controllers.find(controller_id);
  if (i == _controllers.end()) {
    return;
  }

  BAEvent event{};
  event.type = pressed ? BA_JOYBUTTONDOWN : BA_JOYBUTTONUP;
  event.jbutton.button = static_cast<uint8_t>(button);
  event.jbutton.state = pressed ? 1 : 0;
  ballistica::base::g_base->input->PushJoystickEvent(event, i->second);
}

@end
