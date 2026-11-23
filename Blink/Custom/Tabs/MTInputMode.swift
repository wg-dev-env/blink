////////////////////////////////////////////////////////////////////////////////
//
// MoshTerm — Blink Shell フォークへの追加コード（GPL-3.0）
//
// This file is part of a fork of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
////////////////////////////////////////////////////////////////////////////////

import Combine
import SwiftUI

/// 入力モード（英数 / かな / かな・変換中）の置き場（06 §5.2）。
/// 言語は SmarterTermInput.reportLang、変換中は onIME（composition イベント）から流し込む。
final class MTInputModeCenter: ObservableObject {
  static let shared = MTInputModeCenter()

  enum Mode {
    case alnum         // 英数
    case kana          // かな（アプリ内 IME = azooKey）
    case composing     // かな・変換中（アプリ内 IME）
    case systemKana    // かな（iOS の日本語 IME）。azooKey には打鍵が届かない

    var label: String {
      switch self {
      case .alnum: return "英数"
      case .kana: return "かな"
      case .composing: return "かな · 変換中"
      case .systemKana: return "かな · iOS"
      }
    }
  }

  @Published private(set) var lang: String = ""
  @Published private(set) var isComposing = false
  /// アプリ内かな漢字変換（S24）が ON か。システム IME とは独立
  @Published private(set) var inAppKana = false

  private init() {}

  var isJapanese: Bool { lang.hasPrefix("ja") }

  var mode: Mode {
    if inAppKana {
      return isComposing ? .composing : .kana
    }
    // iOS の入力ソースが日本語。azooKey を選んでいても打鍵は Apple IME が先に取るため
    // こちらには届かない。「かな」と出すだけでは azooKey が動いていると誤解するので区別する
    if isJapanese {
      return isComposing ? .composing : .systemKana
    }
    return .alnum
  }

  func setLang(_ lang: String) {
    guard self.lang != lang else { return }
    self.lang = lang
    if !isJapanese && !inAppKana { isComposing = false }
  }

  /// アプリ内かな漢字変換の ON/OFF（MTKanaIME から）
  func setInAppKana(_ on: Bool) {
    guard inAppKana != on else { return }
    inAppKana = on
    if !on { isComposing = false }
  }

  func setComposing(_ composing: Bool) {
    guard isComposing != composing else { return }
    isComposing = composing
  }
}

/// 入力モードピル（06 §5.2）。iPhone はターミナル右下に表示する。
struct MTInputModePill: View {
  @ObservedObject private var center = MTInputModeCenter.shared
  @ObservedObject private var themeStore = MTThemeStore.shared

  private var theme: MTTheme { themeStore.currentTheme }

  var body: some View {
    let mode = center.mode
    let isKana = mode != .alnum
    // azooKey を選んでいるのに iOS の日本語 IME が打鍵を取っている状態は、
    // 動いていないことが分かるよう別の色で出す
    let standsIn = mode == .systemKana && MTKanaIME.shared.engine == .azooKey

    HStack(spacing: 6) {
      ZStack {
        Circle()
          .fill(standsIn ? theme.warn.color : (isKana ? theme.accent.color : theme.text.color))
        Text(isKana ? "あ" : "A")
          .font(MTFont.ui(13, .medium))
          .foregroundColor(theme.bg.color)
      }
      .frame(width: 22, height: 22)

      Text(mode.label)
        .font(MTFont.ui(12, .medium))
        .foregroundColor(theme.sub.color)
        .lineLimit(1)
    }
    .padding(.leading, 5)
    .padding(.trailing, 10)
    .padding(.vertical, 5)
    .background(Capsule().fill(theme.raised.color.opacity(0.92)))
    .overlay(Capsule().stroke(theme.line.color, lineWidth: 1))
    .contentShape(Capsule())
    // かな漢字変換に azooKey を選んでいるときは、タップでも ON/OFF できる。
    // 入力ソースが 2 つ以上あると Ctrl+Space は iPadOS が入力ソース切替に使うため、
    // キーボードから切り替えられない構成があり、その逃げ道にする
    .onTapGesture {
      guard MTKanaIME.shared.engine == .azooKey else { return }
      MTKanaIME.shared.toggle()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("入力モード: \(mode.label)"))
    // ラベルだけでは「azooKey が ON」と「iOS 側が日本語」を区別できないため値で補う
    .accessibilityValue(Text(center.inAppKana ? "アプリ内かな漢字変換 オン" : "アプリ内かな漢字変換 オフ"))
    .accessibilityAddTraits(MTKanaIME.shared.engine == .azooKey ? .isButton : [])
    .accessibilityHint(MTKanaIME.shared.engine == .azooKey
                       ? Text("タップでかな漢字変換を切り替えます") : Text(""))
  }
}
