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

// MARK: - 環境（07「ホストの『環境』」）

/// ホストの環境区分。額縁・危険コマンド・圏外ドラフトの 3 機能がこれを参照する。
@objc public enum MTEnvironment: Int, CaseIterable {
  case none = 0
  case production = 1   // 本番
  case staging = 2      // 検証
  case development = 3  // 開発

  public var label: String {
    switch self {
    case .none: return "なし"
    case .production: return "本番"
    case .staging: return "検証"
    case .development: return "開発"
    }
  }

  /// 危険コマンドの長押し確定を要求するか（本番のみ。設定で全ホストへ広げられる）
  public var requiresDangerGuard: Bool { self == .production }

  /// 圏外ドラフトを必ず確認してから送るか
  public var alwaysConfirmDrafts: Bool { self == .production }

  /// 額縁の既定（環境ごと）。frameStyle が .auto のときに使う
  public var defaultFrame: (style: MTFrameStyle, colorHex: String?) {
    switch self {
    case .production: return (.thick, nil)   // 色は nil = warn 色
    case .staging: return (.thin, nil)       // 色は nil = accent 色
    case .development, .none: return (.none, nil)
    }
  }
}

/// 額縁の太さ
@objc public enum MTFrameStyle: Int, CaseIterable {
  case auto = 0   // 環境の既定にまかせる
  case none = 1
  case thin = 2
  case thick = 3

  public var label: String {
    switch self {
    case .auto: return "環境にまかせる"
    case .none: return "なし"
    case .thin: return "細"
    case .thick: return "太"
    }
  }

  public var width: CGFloat {
    switch self {
    case .auto, .none: return 0
    case .thin: return 2
    case .thick: return 5
    }
  }
}

// MARK: - ホスト設定の解決

/// BKHosts の安全設定を読み出すヘルパー（Obj-C の NSNumber を扱う場所をここに閉じ込める）
public enum MTSafety {

  public static func environment(for host: BKHosts?) -> MTEnvironment {
    guard let raw = host?.environment?.intValue,
          let env = MTEnvironment(rawValue: raw) else { return .none }
    return env
  }

  public static func environment(forAlias alias: String?) -> MTEnvironment {
    guard let alias, !alias.isEmpty else { return .none }
    return environment(for: BKHosts.withHost(alias))
  }

  /// 実際に描く額縁（太さと色）。色は "#RRGGBB" か nil（nil は呼び出し側がテーマ色を当てる）
  public static func frame(for host: BKHosts?) -> (style: MTFrameStyle, colorHex: String?) {
    let env = environment(for: host)
    let raw = host?.frameStyle?.intValue ?? MTFrameStyle.auto.rawValue
    let style = MTFrameStyle(rawValue: raw) ?? .auto
    let color = host?.frameColor
    if style == .auto {
      let def = env.defaultFrame
      return (def.style, color ?? def.colorHex)
    }
    return (style, color)
  }

  /// 額縁の左上に出すラベル（本番のみ）。例「本番 · macmini」
  public static func frameLabel(forAlias alias: String?) -> String? {
    guard let alias, !alias.isEmpty else { return nil }
    let env = environment(forAlias: alias)
    guard env == .production else { return nil }
    return "\(env.label) · \(alias)"
  }
}

// MARK: - 危険コマンド（07 #04）

/// 入力行が「危険」かを判定する。パターンは設定で編集できる。
public enum MTDangerPatterns {
  private static let defaultsKey = "MTDangerPatterns"

  /// 初期値（07 #04 の対象）
  public static let initial: [String] = [
    "reboot",
    "shutdown",
    "rm -rf",
    "DROP",
    "TRUNCATE",
    "git push --force",
    "kubectl delete",
  ]

  public static var current: [String] {
    get {
      let stored = UserDefaults.standard.stringArray(forKey: defaultsKey)
      return stored ?? initial
    }
    set {
      let cleaned = newValue
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
      UserDefaults.standard.set(cleaned, forKey: defaultsKey)
    }
  }

  public static func reset() {
    UserDefaults.standard.removeObject(forKey: defaultsKey)
  }

  /// 入力行がパターンに該当するか。大文字小文字は区別しない（DROP / drop どちらも拾う）
  public static func isDangerous(_ line: String) -> Bool {
    let target = line.lowercased()
    guard !target.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
    return current.contains { pattern in
      let p = pattern.lowercased().trimmingCharacters(in: .whitespaces)
      return !p.isEmpty && target.contains(p)
    }
  }
}
