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

import BlinkConfig
import Combine
import Foundation

/// 覗き見防止で画面を伏せる（07 #08）。
///
/// iOS は「画面を見ているか」をアプリから取れないため（Face ID の注視検出は
/// システム内部機能）、カメラを常時回す代わりに **無操作時間**で伏せる。
/// 目的（隠し忘れても守られる）は満たしつつ、電池とプライバシーの代償を払わない。
final class MTShieldCenter: ObservableObject {
  static let shared = MTShieldCenter()

  private static let enabledKey = "MTShieldEnabled"
  private static let timeoutKey = "MTShieldTimeout"
  private static let requireAuthKey = "MTShieldRequireAuth"

  /// 本番ホストのタブを無操作で伏せる
  @Published var enabled: Bool {
    didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
  }
  /// 伏せるまでの秒数
  @Published var timeout: TimeInterval {
    didSet { UserDefaults.standard.set(timeout, forKey: Self.timeoutKey) }
  }
  /// 戻すときに Face ID を要求する
  @Published var requireAuth: Bool {
    didSet { UserDefaults.standard.set(requireAuth, forKey: Self.requireAuthKey) }
  }

  /// 今伏せているセッション
  @Published private(set) var shielded: Set<UUID> = []

  private var lastInteraction = Date()

  private init() {
    let defaults = UserDefaults.standard
    enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    let stored = defaults.double(forKey: Self.timeoutKey)
    timeout = stored > 0 ? stored : 60
    requireAuth = defaults.object(forKey: Self.requireAuthKey) as? Bool ?? false
  }

  // MARK: - 操作の記録

  /// 打鍵・タップがあったことを知らせる（伏せ時間の起点をリセットする）
  func noteInteraction() {
    lastInteraction = Date()
  }

  var idleSeconds: TimeInterval { Date().timeIntervalSince(lastInteraction) }

  // MARK: - 伏せる / 戻す

  func isShielded(_ key: UUID?) -> Bool {
    guard let key else { return false }
    return shielded.contains(key)
  }

  /// 今すぐ伏せる（メニューからの手動操作）
  func shield(_ key: UUID) {
    guard !shielded.contains(key) else { return }
    shielded.insert(key)
  }

  /// 戻す。Face ID を要求する設定なら認証してから。
  /// 認証できない環境では開かない（fail-closed）。既存の LocalAuth を使い、
  /// 多重プロンプトを防ぐガードも共有する。
  func reveal(_ key: UUID) {
    guard shielded.contains(key) else { return }
    noteInteraction()

    guard requireAuth else {
      shielded.remove(key)
      return
    }

    LocalAuth.shared.authenticate(callback: { [weak self] ok in
      guard ok else { return }  // 失敗・不可時は伏せたまま
      self?.shielded.remove(key)
      self?.noteInteraction()
    }, reason: "伏せている画面を表示します")
  }

  func clear(for key: UUID) {
    shielded.remove(key)
  }

  /// 定期チェック。本番ホストのセッションを無操作で伏せる
  func checkIdle(currentKey: UUID?) {
    guard enabled, let key = currentKey, !shielded.contains(key) else { return }
    guard MTHostContext.shared.environment(for: key) == .production else { return }
    guard idleSeconds >= timeout else { return }
    shield(key)
  }
}
