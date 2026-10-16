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

import Foundation

/// 端末の配色プリセット（S14、[[10_寛容ライセンス部品の活用調査]]§3）。
///
/// 他ツール（VS Code / iTerm / Neovim 等）で広く使われる有名配色の **ANSI 16 色＋背景/前景** を
/// 端末（hterm）に適用するためのデータ。アプリ独自の 8 テーマ（[[06_UIデザイン仕様]]§3）とは
/// 別の層で、UI クロームの配色は独自テーマのまま、端末の中身だけをこのプリセットに差し替える。
///
/// ここは **hex 値の配色データのみ**で、各プロジェクトのコードは取り込まない（ライセンス上の配慮）。
/// 著作権・ライセンス表記はライセンス画面（MTSettingsView）に掲載する。
struct MTTerminalPalette: Identifiable, Equatable {
  let id: String        // 永続化キー
  let name: String      // 表示名（プリセット名の文字列のみ。ロゴ等は使わない）
  let credit: String    // 作者・出典
  let license: String   // ライセンス表記（MIT 等）
  let isDark: Bool
  let bg: MTColor       // 背景
  let fg: MTColor       // 前景（既定文字色）
  let cursor: MTColor   // カーソル
  let ansi: [MTColor]   // ANSI 16 色（0..7 標準＋8..15 明色）

  /// hterm に流す JS。MTTheme.htermJS の **後に** 連結して、背景/前景/カーソル/選択と
  /// 16 色パレットを上書きする（term_set は hterm の prefs にそのまま渡る）。
  var htermJS: String {
    let overrides = ansi.map { "'\($0.css)'" }.joined(separator: ",")
    return [
      "term_set('background-color', '\(bg.css)');",
      "term_set('foreground-color', '\(fg.css)');",
      "term_set('cursor-color', '\(cursor.withAlpha(0.5).css)');",
      // 選択範囲の地色は前景の薄掛け（背景と必ずコントラストが出るように）
      "term_setSelectionColor('\(fg.withAlpha(0.28).css)');",
      "term_set('color-palette-overrides', [\(overrides)]);",
    ].joined(separator: "\n")
  }

  static func named(_ id: String?) -> MTTerminalPalette? {
    guard let id else { return nil }
    return all.first { $0.id == id }
  }

  // MARK: - プリセット定義（canonical な配色値）

  static let all: [MTTerminalPalette] = [
    // Dracula（MIT, Zeno Rocha）https://draculatheme.com/spec
    MTTerminalPalette(
      id: "dracula", name: "Dracula", credit: "Zeno Rocha", license: "MIT", isDark: true,
      bg: MTColor(0x282A36), fg: MTColor(0xF8F8F2), cursor: MTColor(0xF8F8F2),
      ansi: [
        MTColor(0x21222C), MTColor(0xFF5555), MTColor(0x50FA7B), MTColor(0xF1FA8C),
        MTColor(0xBD93F9), MTColor(0xFF79C6), MTColor(0x8BE9FD), MTColor(0xF8F8F2),
        MTColor(0x6272A4), MTColor(0xFF6E6E), MTColor(0x69FF94), MTColor(0xFFFFA5),
        MTColor(0xD6ACFF), MTColor(0xFF92DF), MTColor(0xA4FFFF), MTColor(0xFFFFFF),
      ]),
    // Gruvbox Dark（MIT/X11, Pavel Pertsev）https://github.com/morhetz/gruvbox
    MTTerminalPalette(
      id: "gruvbox-dark", name: "Gruvbox Dark", credit: "Pavel Pertsev", license: "MIT/X11", isDark: true,
      bg: MTColor(0x282828), fg: MTColor(0xEBDBB2), cursor: MTColor(0xEBDBB2),
      ansi: [
        MTColor(0x282828), MTColor(0xCC241D), MTColor(0x98971A), MTColor(0xD79921),
        MTColor(0x458588), MTColor(0xB16286), MTColor(0x689D6A), MTColor(0xA89984),
        MTColor(0x928374), MTColor(0xFB4934), MTColor(0xB8BB26), MTColor(0xFABD2F),
        MTColor(0x83A598), MTColor(0xD3869B), MTColor(0x8EC07C), MTColor(0xEBDBB2),
      ]),
    // Gruvbox Light（MIT/X11, Pavel Pertsev）
    MTTerminalPalette(
      id: "gruvbox-light", name: "Gruvbox Light", credit: "Pavel Pertsev", license: "MIT/X11", isDark: false,
      bg: MTColor(0xFBF1C7), fg: MTColor(0x3C3836), cursor: MTColor(0x3C3836),
      ansi: [
        MTColor(0xFBF1C7), MTColor(0xCC241D), MTColor(0x98971A), MTColor(0xD79921),
        MTColor(0x458588), MTColor(0xB16286), MTColor(0x689D6A), MTColor(0x7C6F64),
        MTColor(0x928374), MTColor(0x9D0006), MTColor(0x79740E), MTColor(0xB57614),
        MTColor(0x076678), MTColor(0x8F3F71), MTColor(0x427B58), MTColor(0x3C3836),
      ]),
    // One Dark（MIT, Atom / GitHub）https://github.com/onedarktheme/onedark
    MTTerminalPalette(
      id: "one-dark", name: "One Dark", credit: "GitHub (Atom)", license: "MIT", isDark: true,
      bg: MTColor(0x282C34), fg: MTColor(0xABB2BF), cursor: MTColor(0x528BFF),
      ansi: [
        MTColor(0x282C34), MTColor(0xE06C75), MTColor(0x98C379), MTColor(0xE5C07B),
        MTColor(0x61AFEF), MTColor(0xC678DD), MTColor(0x56B6C2), MTColor(0xABB2BF),
        MTColor(0x5C6370), MTColor(0xE06C75), MTColor(0x98C379), MTColor(0xE5C07B),
        MTColor(0x61AFEF), MTColor(0xC678DD), MTColor(0x56B6C2), MTColor(0xFFFFFF),
      ]),
    // Tokyo Night（Apache-2.0, folke）https://github.com/folke/tokyonight.nvim
    MTTerminalPalette(
      id: "tokyonight-night", name: "Tokyo Night", credit: "folke", license: "Apache-2.0", isDark: true,
      bg: MTColor(0x1A1B26), fg: MTColor(0xC0CAF5), cursor: MTColor(0xC0CAF5),
      ansi: [
        MTColor(0x15161E), MTColor(0xF7768E), MTColor(0x9ECE6A), MTColor(0xE0AF68),
        MTColor(0x7AA2F7), MTColor(0xBB9AF7), MTColor(0x7DCFFF), MTColor(0xA9B1D6),
        MTColor(0x414868), MTColor(0xF7768E), MTColor(0x9ECE6A), MTColor(0xE0AF68),
        MTColor(0x7AA2F7), MTColor(0xBB9AF7), MTColor(0x7DCFFF), MTColor(0xC0CAF5),
      ]),
    // Tokyo Night Day（Apache-2.0, folke）
    MTTerminalPalette(
      id: "tokyonight-day", name: "Tokyo Night Day", credit: "folke", license: "Apache-2.0", isDark: false,
      bg: MTColor(0xE1E2E7), fg: MTColor(0x3760BF), cursor: MTColor(0x3760BF),
      ansi: [
        MTColor(0xB4B5B9), MTColor(0xF52A65), MTColor(0x587539), MTColor(0x8C6C3E),
        MTColor(0x2E7DE9), MTColor(0x9854F1), MTColor(0x007197), MTColor(0x6172B0),
        MTColor(0xA1A6C5), MTColor(0xF52A65), MTColor(0x587539), MTColor(0x8C6C3E),
        MTColor(0x2E7DE9), MTColor(0x9854F1), MTColor(0x007197), MTColor(0x3760BF),
      ]),
    // Solarized Dark（MIT, Ethan Schoonover）https://ethanschoonover.com/solarized
    MTTerminalPalette(
      id: "solarized-dark", name: "Solarized Dark", credit: "Ethan Schoonover", license: "MIT", isDark: true,
      bg: MTColor(0x002B36), fg: MTColor(0x839496), cursor: MTColor(0x839496),
      ansi: [
        MTColor(0x073642), MTColor(0xDC322F), MTColor(0x859900), MTColor(0xB58900),
        MTColor(0x268BD2), MTColor(0xD33682), MTColor(0x2AA198), MTColor(0xEEE8D5),
        MTColor(0x002B36), MTColor(0xCB4B16), MTColor(0x586E75), MTColor(0x657B83),
        MTColor(0x839496), MTColor(0x6C71C4), MTColor(0x93A1A1), MTColor(0xFDF6E3),
      ]),
    // Solarized Light（MIT, Ethan Schoonover）
    MTTerminalPalette(
      id: "solarized-light", name: "Solarized Light", credit: "Ethan Schoonover", license: "MIT", isDark: false,
      bg: MTColor(0xFDF6E3), fg: MTColor(0x657B83), cursor: MTColor(0x657B83),
      ansi: [
        MTColor(0x073642), MTColor(0xDC322F), MTColor(0x859900), MTColor(0xB58900),
        MTColor(0x268BD2), MTColor(0xD33682), MTColor(0x2AA198), MTColor(0xEEE8D5),
        MTColor(0x002B36), MTColor(0xCB4B16), MTColor(0x586E75), MTColor(0x657B83),
        MTColor(0x839496), MTColor(0x6C71C4), MTColor(0x93A1A1), MTColor(0xFDF6E3),
      ]),
    // Catppuccin Mocha（MIT, Catppuccin）https://github.com/catppuccin/catppuccin
    MTTerminalPalette(
      id: "catppuccin-mocha", name: "Catppuccin Mocha", credit: "Catppuccin", license: "MIT", isDark: true,
      bg: MTColor(0x1E1E2E), fg: MTColor(0xCDD6F4), cursor: MTColor(0xF5E0DC),
      ansi: [
        MTColor(0x45475A), MTColor(0xF38BA8), MTColor(0xA6E3A1), MTColor(0xF9E2AF),
        MTColor(0x89B4FA), MTColor(0xF5C2E7), MTColor(0x94E2D5), MTColor(0xBAC2DE),
        MTColor(0x585B70), MTColor(0xF38BA8), MTColor(0xA6E3A1), MTColor(0xF9E2AF),
        MTColor(0x89B4FA), MTColor(0xF5C2E7), MTColor(0x94E2D5), MTColor(0xA6ADC8),
      ]),
    // Catppuccin Latte（MIT, Catppuccin）
    MTTerminalPalette(
      id: "catppuccin-latte", name: "Catppuccin Latte", credit: "Catppuccin", license: "MIT", isDark: false,
      bg: MTColor(0xEFF1F5), fg: MTColor(0x4C4F69), cursor: MTColor(0xDC8A78),
      ansi: [
        MTColor(0x5C5F77), MTColor(0xD20F39), MTColor(0x40A02B), MTColor(0xDF8E1D),
        MTColor(0x1E66F5), MTColor(0xEA76CB), MTColor(0x179299), MTColor(0xACB0BE),
        MTColor(0x6C6F85), MTColor(0xD20F39), MTColor(0x40A02B), MTColor(0xDF8E1D),
        MTColor(0x1E66F5), MTColor(0xEA76CB), MTColor(0x179299), MTColor(0xBCC0CC),
      ]),
  ]
}
