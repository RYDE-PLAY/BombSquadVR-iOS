// Small UIKit pasteboard bridge used by Ballistica's iOS adapter.

#ifndef BOMBSQUADVR_BALLISTICA_UIKIT_PASTEBOARD_H_
#define BOMBSQUADVR_BALLISTICA_UIKIT_PASTEBOARD_H_

#include <functional>
#include <optional>
#include <string>

namespace ballistica::base {

auto UIKitPasteboardHasText() -> bool;
void UIKitPasteboardSetText(const std::string& text);
void UIKitPasteboardGetTextAsync(
    std::function<void(std::optional<std::string>)> completion);

}  // namespace ballistica::base

#endif  // BOMBSQUADVR_BALLISTICA_UIKIT_PASTEBOARD_H_
