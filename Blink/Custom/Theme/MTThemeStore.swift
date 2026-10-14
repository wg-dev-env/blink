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

/// 選択テーマと外観モードの保存・適用（06 §3）。
/// テーマ未選択（nil）の間は既存 Blink の挙動を一切変えない。
final class MTThemeStore: ObservableObject {

  /// 外観モード（06 §3。テーマとは別項目）
  enum AppearanceMode: String, CaseIterable {
    case system  // システムに合わせる
    case theme   // 常にテーマどおり
  }

  static let shared = MTThemeStore()

  private static let themeKey = "MTSelectedThemeID"
  private static let modeKey = "MTAppearanceMode"

  @Published private(set) var selectedThemeID: String?
  @Published var appearanceMode: AppearanceMode {
    didSet {
      guard appearanceMode != oldValue else { return }
      UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.modeKey)
      notifyAppearanceChanged()
    }
  }

  private init() {
    let defaults = UserDefaults.standard
    selectedThemeID = defaults.string(forKey: Self.themeKey)
    appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .system
  }

  var selectedTheme: MTTheme? {
    selectedThemeID.flatMap { id in MTTheme.all.first { $0.id == id } }
  }

  /// UIKit に適用する外観。テーマ未選択なら nil（既存の keyboardStyle 設定に委ねる）。
  var overrideInterfaceStyle: UIUserInterfaceStyle? {
    guard let theme = selectedTheme else { return nil }
    switch appearanceMode {
    case .system: return .unspecified
    case .theme: return theme.isLight ? .light : .dark
    }
  }

  /// テーマを選択し、ターミナル・UI の両方へ即時反映する（06 §3「選ぶと即時に全画面へ反映」）
  func select(_ theme: MTTheme) {
    selectedThemeID = theme.id
    UserDefaults.standard.set(theme.id, forKey: Self.themeKey)
    applyToTerminalStyle(theme)
    notifyAppearanceChanged()
    applyToLiveSessions(theme)
  }

  /// ターミナル側の選択スタイル（TerminalStyleStore）の themeName を差し替える
  private func applyToTerminalStyle(_ theme: MTTheme) {
    let store = TerminalStyleStore.shared
    if store.selectedStyleID == nil {
      // 組み込み Default は編集不可のため、Custom スタイルを作って選択する
      // （StyleCustomizationView.ensureEditableStyle と同じ流儀）
      let base = store.builtInDefault
      let custom = store.createStyle(
        name: "Custom",
        themeName: theme.name,
        fontName: base.fontName,
        fontSize: base.fontSize,
        cursorBlink: base.cursorBlink,
        boldMode: base.boldMode,
        boldAsBright: base.boldAsBright
      )
      store.setSelected(custom.id)
    } else {
      store.setStyleThemeName(theme.name)
    }
    BLKDefaults.save()
  }

  private func notifyAppearanceChanged() {
    NotificationCenter.default.post(
      name: NSNotification.Name(BKAppearanceChanged), object: nil)
  }

  /// 開いているセッションのターミナルにもその場で適用する
  private func applyToLiveSessions(_ theme: MTTheme) {
    SessionRegistry.shared.forEachSession { session in
      (session as? TermController)?.termView.applyTheme(theme.name)
    }
  }
}
