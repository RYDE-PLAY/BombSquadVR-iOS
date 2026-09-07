// Local C++ surface for the generated BallisticaKit-Swift.h API used by the
// public Apple adapter/platform sources.  The Swift implementation lives in
// BombSquadVRBallisticaHost.mm for this standalone iOS VR target.

#ifndef BOMBSQUADVR_BALLISTICAKIT_SWIFT_H_
#define BOMBSQUADVR_BALLISTICAKIT_SWIFT_H_

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace ballistica {
class Runnable;
}  // namespace ballistica

namespace BallisticaKit {

class OptionalCString {
 public:
  OptionalCString() = default;
  explicit OptionalCString(const char* value) : value_{value} {}

  explicit operator bool() const { return value_ != nullptr; }
  auto get() const -> const char* { return value_; }

 private:
  const char* value_{};
};

class FloatArray5 {
 public:
  FloatArray5() = default;
  FloatArray5(float left, float right, float bottom, float top, float width)
      : values_{left, right, bottom, top, width} {}

  auto getCount() const -> int { return 5; }
  auto operator[](int index) const -> float { return values_[index]; }

 private:
  float values_[5]{};
};

class TextTextureData {
 public:
  TextTextureData() = default;
  explicit TextTextureData(std::vector<std::uint8_t> pixels)
      : pixels_{std::move(pixels)} {}
  TextTextureData(const TextTextureData&) = delete;
  auto operator=(const TextTextureData&) -> TextTextureData& = delete;
  TextTextureData(TextTextureData&&) noexcept = default;
  auto operator=(TextTextureData&&) noexcept -> TextTextureData& = default;

  static auto init(int width, int height,
                   const std::vector<std::string>& strings,
                   const std::vector<float>& positions,
                   const std::vector<float>& widths, float scale)
      -> TextTextureData;

  static auto getTextBoundsAndWidth(const std::string& text) -> FloatArray5;

  auto getTextTextureData() -> void* { return pixels_.data(); }

 private:
  std::vector<std::uint8_t> pixels_;
};

class FromCpp {
 public:
  static void pushRawRunnableToMain(ballistica::Runnable* runnable);
  static auto getOSVersion() -> const char*;
  static auto getApplicationSupportDirectoryPath() -> const char*;
  static auto getCacheDirectoryPath() -> const char*;
  static auto getResourcesPath() -> const char*;
  static auto getBaLocale() -> const char*;
  static auto getLocaleTag() -> const char*;
  static void startNetAvailabilityMonitoring();

  // MFi haptics are not used by the VR controller bridge. Keep the public
  // Apple adapter calls harmless for controllers that report no platform id.
  static void playControllerHaptic(int, float, float, float) {}
  static void stopControllerHaptic(int) {}
};

class UIKitFromCpp {
 public:
  static auto getDeviceName() -> const char*;
  static auto getLegacyDeviceUUID() -> const char*;
  static auto isTablet() -> bool;
  static void openURL(const std::string& url);
  static void invokeStringEditor(const std::string& title,
                                 const std::string& value, int max_chars,
                                 bool is_password, const std::string& kind);
};

// These APIs are compiled out on iOS, but the Apple sources include their
// declarations for the macOS branches as well.
class CocoaFromCpp {
 public:
  static auto getDeviceName() -> const char* { return "Mac"; }
  static auto getDeviceModelName() -> const char* { return "Mac"; }
  static auto getLegacyDeviceUUID() -> const char* {
    return "bombsquadvr-mac-uuid";
  }
  static auto getApplicationSupportPath() -> const char* { return "/tmp"; }
  static void setCursorVisible(bool) {}
  static void terminateApp() {}
  static auto getMainWindowIsFullscreen() -> bool { return false; }
  static void setMainWindowFullscreen(bool) {}
  static auto getKeyRepeatDelay() -> float { return 0.5f; }
  static auto getKeyRepeatInterval() -> float { return 0.05f; }
  static auto clipboardIsSupported() -> bool { return false; }
  static auto clipboardHasText() -> bool { return false; }
  static void clipboardSetText(const std::string&) {}
  static auto clipboardGetText() -> OptionalCString { return {}; }
  static void openURL(const std::string&) {}
  static auto haveOverlayWebBrowser() -> bool { return false; }
  static void openURLInOverlayWebBrowser(const std::string&) {}
  static void closeOverlayWebBrowser() {}
  static void openDirExternally(const std::string&) {}
  static void openFileExternally(const std::string&) {}
  static void blockingFatalErrorDialog(const std::string&) {}
  static void macMusicAppInit() {}
  static auto macMusicAppGetVolume() -> int { return 100; }
  static void macMusicAppSetVolume(int) {}
  static void macMusicAppStop() {}
  static auto macMusicAppPlayPlaylist(const std::string&) -> bool {
    return false;
  }
  static void macMusicAppGetPlaylists() {}
};

class StoreKitContext {
 public:
  static void onAppStart() {}
  static void requestReview() {}
  static void purchase(const std::string&) {}
  static void restorePurchases() {}
  static void purchaseAck(const std::string&, const std::string&) {}
};

class GameCenterContext {
 public:
  static void onAppStart() {}
  static void getSignInToken(int) {}
  static void backEndActiveChange(bool) {}
  static void submitScore(const std::string&, const std::string&, int64_t) {}
  static void reportAchievement(const std::string&) {}
  static void resetAchievements() {}
  static auto haveLeaderboard(const std::string&, const std::string&) -> bool {
    return false;
  }
  static void showGameServiceUI(const std::string&, const std::string&,
                                const std::string&) {}
};

}  // namespace BallisticaKit

#endif  // BOMBSQUADVR_BALLISTICAKIT_SWIFT_H_
