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
    case alnum      // 英数
    case kana       // かな
    case composing  // かな・変換中

    var label: String {
      switch self {
      case .alnum: return "英数"
      case .kana: return "かな"
      case .composing: return "かな · 変換中"
      }
    }
  }

  @Published private(set) var lang: String = ""
  @Published private(set) var isComposing = false

  private init() {}

  var isJapanese: Bool { lang.hasPrefix("ja") }

  var mode: Mode {
    if isJapanese {
      return isComposing ? .composing : .kana
    }
    return .alnum
  }

  func setLang(_ lang: String) {
    guard self.lang != lang else { return }
    self.lang = lang
    if !isJapanese { isComposing = false }
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

  private var theme: MTTheme { themeStore.selectedTheme ?? MTTheme.all[0] }

  var body: some View {
    let mode = center.mode
    let isKana = mode != .alnum

    HStack(spacing: 6) {
      ZStack {
        Circle()
          .fill(isKana ? theme.accent.color : theme.text.color)
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
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("入力モード: \(mode.label)"))
  }
}
