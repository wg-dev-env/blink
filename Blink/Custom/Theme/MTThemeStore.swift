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

  /// 差分の配色（06 §5.5）。既定は橙 / 青（赤緑の色覚差に配慮）
  enum DiffPalette: String, CaseIterable {
    case orangeBlue  // 橙（元）/ 青（変更後）
    case redGreen    // 従来の赤 / 緑
  }

  static let shared = MTThemeStore()

  private static let themeKey = "MTSelectedThemeID"
  private static let modeKey = "MTAppearanceMode"
  private static let diffKey = "MTDiffPalette"
  private static let terminalPaletteKey = "MTSelectedTerminalPaletteID"

  @Published private(set) var selectedThemeID: String?
  /// 端末の配色プリセット（S14）。nil = 「テーマに従う」（従来どおり）
  @Published private(set) var selectedPaletteID: String?
  @Published var appearanceMode: AppearanceMode {
    didSet {
      guard appearanceMode != oldValue else { return }
      UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.modeKey)
      notifyAppearanceChanged()
    }
  }
  @Published var diffPalette: DiffPalette {
    didSet {
      guard diffPalette != oldValue else { return }
      UserDefaults.standard.set(diffPalette.rawValue, forKey: Self.diffKey)
    }
  }

  private init() {
    let defaults = UserDefaults.standard
    selectedThemeID = defaults.string(forKey: Self.themeKey)
    selectedPaletteID = defaults.string(forKey: Self.terminalPaletteKey)
    appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .system
    diffPalette = DiffPalette(rawValue: defaults.string(forKey: Self.diffKey) ?? "") ?? .orangeBlue
  }

  /// 選択中の端末配色プリセット（nil = テーマに従う）
  var selectedPalette: MTTerminalPalette? {
    selectedPaletteID.flatMap { MTTerminalPalette.named($0) }
  }

  /// 端末の配色プリセットを選ぶ（nil でクリア＝テーマに従う）。
  /// 端末の見た目だけを差し替え、UI クロームは選択中テーマのまま。即時反映する。
  func selectPalette(_ palette: MTTerminalPalette?) {
    selectedPaletteID = palette?.id
    if let id = palette?.id {
      UserDefaults.standard.set(id, forKey: Self.terminalPaletteKey)
    } else {
      UserDefaults.standard.removeObject(forKey: Self.terminalPaletteKey)
    }
    // htermJS は適用時に selectedPalette を読むので、現在テーマを再適用すれば反映される
    applyToLiveSessions(currentTheme)
  }

  /// 現在の設定での diff 配色（文字色・地色）。赤 / 緑選択時はテーマによらず共通値。
  var diffColors: (delText: MTColor, delBg: MTColor, addText: MTColor, addBg: MTColor) {
    let theme = currentTheme
    switch diffPalette {
    case .orangeBlue:
      return (theme.diffDelText, theme.diffDelBg, theme.diffAddText, theme.diffAddBg)
    case .redGreen:
      return (MTColor(0xE06C60), MTColor(r: 224, g: 90, b: 80, a: 0.16),
              MTColor(0x6FBF73), MTColor(r: 90, g: 190, b: 110, a: 0.16))
    }
  }

  var selectedTheme: MTTheme? {
    selectedThemeID.flatMap { id in MTTheme.all.first { $0.id == id } }
  }

  /// 表示に使うテーマ（未選択時は既定の「黒」）。
  /// 「既定 = 先頭」の規則はここ 1 か所に閉じ込める。
  var currentTheme: MTTheme { selectedTheme ?? MTTheme.all[0] }

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

  /// 起動時に、ターミナル側スタイルの themeName が選択テーマとずれていたら直す。
  /// （スタイルの再生成・移行などで同期が切れた場合の自己修復。UI はテーマ色なのに
  /// ターミナルだけ旧配色のままになる症状を防ぐ）
  func syncTerminalStyleIfNeeded() {
    guard let theme = selectedTheme else { return }
    if MTTheme.named(TerminalStyleStore.shared.selectedStyle.themeName)?.id != theme.id {
      applyToTerminalStyle(theme)
    }
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
