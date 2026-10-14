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
import Foundation
import UIKit

/// セッションの接続状態（06 §4）。色＋形の二重表現で表示する。
enum MTSessionState {
  case connected     // 接続中（ok・塗り丸）
  case reconnecting  // 再接続中（warn・輪）
  case held          // 保持＝回線断（bad・横棒）
  case restored      // 復元済み（accent・角丸四角）

  /// VoiceOver 用の読み上げ
  var label: String {
    switch self {
    case .connected: return "接続中"
    case .reconnecting: return "再接続中"
    case .held: return "保持中"
    case .restored: return "復元済み"
    }
  }
}

/// セッション状態の置き場（セッションキー → 状態）。
/// S3 では表示側のみ。実際の状態遷移（SSH/Mosh の接続イベントとの配線）は S4 で行う。
final class MTSessionStateCenter: ObservableObject {
  static let shared = MTSessionStateCenter()

  @Published private(set) var states: [UUID: MTSessionState] = [:]

  private init() {}

  func state(for key: UUID) -> MTSessionState {
    states[key] ?? .connected
  }

  func set(_ state: MTSessionState, for key: UUID) {
    states[key] = state
  }

  func clear(for key: UUID) {
    states.removeValue(forKey: key)
  }
}

/// Obj-C（LayoutConstraintManager.m）から参照するレイアウト定数。
/// タブバー設置時に SpaceController が設定し、端末ビューの上インセットに加算される。
@objc class MTChrome: NSObject {
  @objc static var tabBarTopInset: CGFloat = 0
}
