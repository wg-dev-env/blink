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

import SwiftUI
import UIKit

/// 書体（06 §1）: UI = IBM Plex Sans JP、等幅 = JetBrains Mono（400/500/700）。
/// いずれも OFL でアプリ同梱（`Blink/Custom/Fonts/`、ライセンス全文は同フォルダの OFL-*.txt）。
/// フォントが読めない環境ではシステム書体へフォールバックする。
enum MTFont {

  enum Weight {
    case regular  // 400
    case medium   // 500
    case bold     // 700

    var uiKit: UIFont.Weight {
      switch self {
      case .regular: return .regular
      case .medium: return .medium
      case .bold: return .bold
      }
    }
  }

  // PostScript 名（UIAppFonts で登録済み）
  private static func uiName(_ weight: Weight) -> String {
    switch weight {
    case .regular: return "IBMPlexSansJP-Regular"
    case .medium: return "IBMPlexSansJP-Medium"
    case .bold: return "IBMPlexSansJP-Bold"
    }
  }

  private static func monoName(_ weight: Weight) -> String {
    switch weight {
    case .regular: return "JetBrainsMono-Regular"
    case .medium: return "JetBrainsMono-Medium"
    case .bold: return "JetBrainsMono-Bold"
    }
  }

  // MARK: - SwiftUI（ダイナミックタイプ対応: relativeTo で拡縮する）

  static func ui(_ size: CGFloat, _ weight: Weight = .regular,
                 relativeTo style: Font.TextStyle = .body) -> Font {
    Font.custom(uiName(weight), size: size, relativeTo: style)
  }

  static func mono(_ size: CGFloat, _ weight: Weight = .regular,
                   relativeTo style: Font.TextStyle = .body) -> Font {
    Font.custom(monoName(weight), size: size, relativeTo: style)
  }

  // MARK: - UIKit

  static func uiFont(size: CGFloat, weight: Weight = .regular) -> UIFont {
    UIFont(name: uiName(weight), size: size)
      ?? .systemFont(ofSize: size, weight: weight.uiKit)
  }

  static func monoFont(size: CGFloat, weight: Weight = .regular) -> UIFont {
    UIFont(name: monoName(weight), size: size)
      ?? .monospacedSystemFont(ofSize: size, weight: weight.uiKit)
  }
}
