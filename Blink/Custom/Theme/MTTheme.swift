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

// MARK: - MTColor

/// 配色トークン 1 色。値の正は Obsidian「06_UIデザイン仕様 §3.1」の表。
struct MTColor: Equatable {
  let r: Int
  let g: Int
  let b: Int
  let a: Double

  init(_ hex: UInt32, alpha: Double = 1.0) {
    self.r = Int((hex >> 16) & 0xFF)
    self.g = Int((hex >> 8) & 0xFF)
    self.b = Int(hex & 0xFF)
    self.a = alpha
  }

  init(r: Int, g: Int, b: Int, a: Double) {
    self.r = r
    self.g = g
    self.b = b
    self.a = a
  }

  var css: String {
    if a >= 1.0 {
      return String(format: "#%02X%02X%02X", r, g, b)
    }
    return "rgba(\(r),\(g),\(b),\(a))"
  }

  var uiColor: UIColor {
    UIColor(red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a))
  }

  var color: Color { Color(uiColor) }

  /// "#RRGGBB" から作る（額縁の色など、保存された文字列を戻すのに使う）
  init?(hex: String) {
    var text = hex.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
    self.init(value)
  }

  var hexString: String { String(format: "#%02X%02X%02X", r, g, b) }

  func withAlpha(_ alpha: Double) -> MTColor {
    MTColor(r: r, g: g, b: b, a: alpha)
  }
}

// MARK: - MTTheme

/// 配色テーマ（8 種）。トークン名・値とも 06 §3.1 と同値に保つこと。
struct MTTheme: Identifiable, Equatable {
  let id: String        // 永続化キー
  let name: String      // 和名。TerminalStyle.themeName にもこの値が入る
  let subtitle: String  // ラテン表記
  let isLight: Bool     // 白・駒鳥のみライト扱い（06 §3）
  let summary: String   // 設定画面に出す説明文（06 §3.2）

  let bg: MTColor
  let surface: MTColor
  let raised: MTColor
  let line: MTColor
  let text: MTColor
  let sub: MTColor
  let muted: MTColor
  let term: MTColor     // 端末文字
  let ghost: MTColor    // 予測エコー
  let accent: MTColor   // カーソル・選択・IME
  let ok: MTColor       // 接続中
  let okBg: MTColor     // アクティブタブ地
  let warn: MTColor     // 再接続中
  let bad: MTColor      // 保持・切断
  let diffDelText: MTColor
  let diffDelBg: MTColor
  let diffAddText: MTColor
  let diffAddBg: MTColor
  let toggleOff: MTColor

  /// 復元済み状態は accent と同値（06 §3.1）
  var restore: MTColor { accent }

  /// 改名したテーマの旧名 → id（保存済みの themeName を解決するため）
  private static let legacyNames: [String: String] = ["駒鳥": "robin"]

  static func named(_ name: String?) -> MTTheme? {
    guard let name else { return nil }
    let id = Self.legacyNames[name]
    return all.first { $0.name == name || $0.id == name || $0.id == id }
  }

  static let all: [MTTheme] = [
    MTTheme(
      id: "kuro", name: "黒", subtitle: "Kuro", isLight: false,
      summary: "有機EL向けの純黒。夜間や電池を気にする時に。",
      bg: MTColor(0x000000), surface: MTColor(0x0F1011), raised: MTColor(0x17191B),
      line: MTColor(0x26292C), text: MTColor(0xF2F2F0), sub: MTColor(0xC9CCCE),
      muted: MTColor(0x9A9FA3), term: MTColor(0xDADCDA), ghost: MTColor(0x5E6367),
      accent: MTColor(0x8AB8FF), ok: MTColor(0x46C08F), okBg: MTColor(0x0E1F17),
      warn: MTColor(0xF0B44C), bad: MTColor(0xF2685F),
      diffDelText: MTColor(0xF3A766), diffDelBg: MTColor(r: 240, g: 140, b: 60, a: 0.18),
      diffAddText: MTColor(0x9CC6FF), diffAddBg: MTColor(r: 90, g: 160, b: 255, a: 0.18),
      toggleOff: MTColor(0x3A3E42)
    ),
    MTTheme(
      id: "sumi", name: "墨", subtitle: "Sumi", isLight: false,
      summary: "墨地に生成りの文字。長時間でも目が楽。",
      bg: MTColor(0x16191E), surface: MTColor(0x1E232A), raised: MTColor(0x262C34),
      line: MTColor(0x323944), text: MTColor(0xF4F0E6), sub: MTColor(0xD4CEC1),
      muted: MTColor(0x9A9384), term: MTColor(0xE6E0D3), ghost: MTColor(0x6B6459),
      accent: MTColor(0x93B6D9), ok: MTColor(0x5DB58A), okBg: MTColor(0x1B2A24),
      warn: MTColor(0xE3B04B), bad: MTColor(0xE8665A),
      diffDelText: MTColor(0xE8A06A), diffDelBg: MTColor(r: 224, g: 150, b: 90, a: 0.16),
      diffAddText: MTColor(0x8FBCE0), diffAddBg: MTColor(r: 110, g: 160, b: 210, a: 0.18),
      toggleOff: MTColor(0x3E4652)
    ),
    MTTheme(
      id: "mos", name: "MOS", subtitle: "苔", isLight: false,
      summary: "苔むした深緑の地。落ち着いた緑で、状態色とも喧嘩しない。",
      bg: MTColor(0x111813), surface: MTColor(0x18221B), raised: MTColor(0x202C23),
      line: MTColor(0x2C3B30), text: MTColor(0xE8EFE4), sub: MTColor(0xC6D2C4),
      muted: MTColor(0x93A596), term: MTColor(0xD9E3D5), ghost: MTColor(0x5E6F61),
      accent: MTColor(0xC9D98A), ok: MTColor(0x5CC7A0), okBg: MTColor(0x16291F),
      warn: MTColor(0xE9B95A), bad: MTColor(0xEE6D60),
      diffDelText: MTColor(0xEBA56E), diffDelBg: MTColor(r: 235, g: 165, b: 110, a: 0.16),
      diffAddText: MTColor(0x96C4EA), diffAddBg: MTColor(r: 120, g: 170, b: 230, a: 0.16),
      toggleOff: MTColor(0x384A3D)
    ),
    MTTheme(
      id: "shiro", name: "白", subtitle: "Shiro", isLight: true,
      summary: "屋外の直射日光でも読める明るい配色。",
      bg: MTColor(0xFAFAF7), surface: MTColor(0xFFFFFF), raised: MTColor(0xF1F2EF),
      line: MTColor(0xD9DDDF), text: MTColor(0x1A1F23), sub: MTColor(0x3A444B),
      muted: MTColor(0x5A646B), term: MTColor(0x2A3237), ghost: MTColor(0xA3ABB0),
      accent: MTColor(0x2A6FE0), ok: MTColor(0x1F8A5F), okBg: MTColor(0xE6F3EC),
      warn: MTColor(0xA86A00), bad: MTColor(0xC8372F),
      diffDelText: MTColor(0xB4560F), diffDelBg: MTColor(r: 230, g: 130, b: 40, a: 0.14),
      diffAddText: MTColor(0x1C55B5), diffAddBg: MTColor(r: 42, g: 111, b: 224, a: 0.12),
      toggleOff: MTColor(0xC3C9CC)
    ),
    MTTheme(
      // 旧「駒鳥」。id は選択状態の互換のため robin のまま（2026-10-15 改定、06 §3.3）
      id: "robin", name: "セルリアン", subtitle: "Cerulean", isLight: true,
      summary: "セルリアングリーンの明るい青緑。明るい屋内向けのライト配色。",
      bg: MTColor(0xCFEFE9), surface: MTColor(0xF3FBF9), raised: MTColor(0xE2F5F1),
      line: MTColor(0xA9DCD3), text: MTColor(0x0C2B27), sub: MTColor(0x1E4942),
      muted: MTColor(0x3C6B63), term: MTColor(0x11332E), ghost: MTColor(0x7FB4AC),
      accent: MTColor(0x0FB5A6), ok: MTColor(0x0E8C66), okBg: MTColor(0xD4F0E3),
      warn: MTColor(0x9A6200), bad: MTColor(0xC23A32),
      diffDelText: MTColor(0xA9520E), diffDelBg: MTColor(r: 230, g: 130, b: 40, a: 0.14),
      diffAddText: MTColor(0x1C55B5), diffAddBg: MTColor(r: 42, g: 111, b: 224, a: 0.12),
      toggleOff: MTColor(0x9CCFC6)
    ),
    MTTheme(
      id: "canvas", name: "帆布", subtitle: "Canvas", isLight: false,
      summary: "トランクの革とキャンバスを思わせる焦茶に、金茶の差し色。",
      bg: MTColor(0x1E160F), surface: MTColor(0x2A1F15), raised: MTColor(0x33261A),
      line: MTColor(0x47372A), text: MTColor(0xF1E6CF), sub: MTColor(0xD9CBB0),
      muted: MTColor(0xA8977A), term: MTColor(0xE8DCC3), ghost: MTColor(0x6E5E48),
      accent: MTColor(0xD8B878), ok: MTColor(0x6CC08F), okBg: MTColor(0x22301F),
      warn: MTColor(0xF09A45), bad: MTColor(0xF06A5C),
      diffDelText: MTColor(0xF0A36A), diffDelBg: MTColor(r: 240, g: 150, b: 90, a: 0.16),
      diffAddText: MTColor(0x9CC3E8), diffAddBg: MTColor(r: 120, g: 170, b: 230, a: 0.16),
      toggleOff: MTColor(0x4E3E2E)
    ),
    MTTheme(
      id: "verde", name: "翠紅", subtitle: "Verde", isLight: false,
      summary: "深いエメラルドの地にアイボリーと金。",
      bg: MTColor(0x0A2A1E), surface: MTColor(0x10362A), raised: MTColor(0x154233),
      line: MTColor(0x1F5241), text: MTColor(0xF3EFE2), sub: MTColor(0xD6D8C9),
      muted: MTColor(0x9FB8A9), term: MTColor(0xE6E8DA), ghost: MTColor(0x5D8070),
      accent: MTColor(0xE6CF95), ok: MTColor(0x5FD3A6), okBg: MTColor(0x12402F),
      warn: MTColor(0xF2B64C), bad: MTColor(0xFF6F61),
      diffDelText: MTColor(0xF3A66E), diffDelBg: MTColor(r: 240, g: 150, b: 90, a: 0.16),
      diffAddText: MTColor(0xA0C8EE), diffAddBg: MTColor(r: 120, g: 170, b: 230, a: 0.16),
      toggleOff: MTColor(0x2C5A49)
    ),
    MTTheme(
      id: "rosso", name: "緋", subtitle: "Rosso", isLight: false,
      summary: "深いボルドーの地に金の差し色。切断の赤とは明るさで区別。",
      bg: MTColor(0x2A0E12), surface: MTColor(0x37151A), raised: MTColor(0x431B21),
      line: MTColor(0x58262D), text: MTColor(0xF7EBDD), sub: MTColor(0xE3D2C2),
      muted: MTColor(0xB89A92), term: MTColor(0xEFE1D3), ghost: MTColor(0x7A5A55),
      accent: MTColor(0xE0BE72), ok: MTColor(0x6CCB96), okBg: MTColor(0x23281C),
      warn: MTColor(0xF5B651), bad: MTColor(0xFF8A7A),
      diffDelText: MTColor(0xF3A36E), diffDelBg: MTColor(r: 240, g: 150, b: 90, a: 0.16),
      diffAddText: MTColor(0xA6CAEE), diffAddBg: MTColor(r: 120, g: 170, b: 230, a: 0.18),
      toggleOff: MTColor(0x5E2F35)
    ),
  ]
}

// MARK: - hterm 連携

extension MTTheme {
  /// hterm に流す JS。TermView の既存適用経路（テーマ JS の evaluate）にそのまま乗る。
  /// ANSI 16 色は 06 に未定義のため上書きしない（hterm 既定のまま）。
  var htermJS: String {
    [
      "term_set('background-color', '\(bg.css)');",
      "term_set('foreground-color', '\(term.css)');",
      // カーソルは hterm の慣習に合わせて半透明の accent
      "term_set('cursor-color', '\(accent.withAlpha(0.5).css)');",
    ].joined(separator: "\n")
  }
}

/// Obj-C（TermView.m）から MTTheme を引くための橋渡し
@objc class MTThemeBridge: NSObject {
  /// テーマ名が MTTheme なら hterm 用 JS を返す。該当しなければ nil（既存の BKTheme 経路に委ねる）。
  @objc static func htermJS(forName name: String?) -> String? {
    MTTheme.named(name)?.htermJS
  }
}
