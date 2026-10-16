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

/// セッションごとの tmux セッション名の対応表（要件4「複数接続」）。
///
/// 同じホストへ複数回 Mosh 接続したとき、全部が `tmux new -A -s main` で同じ tmux
/// セッションに合流して画面が鏡写しになるのを防ぐ。新規接続には、同じホストの生存
/// セッションと衝突しないユニークな名前（`main` → `main-2` → `main-3` …）を割り当てる。
///
/// 割り当てた名前は接続コマンドに埋め込まれるため、Mosh は encoded state の復元で、
/// SSH は reconnectionCommand の再実行で、どちらも同じ tmux セッションへ戻る（「切れない」）。
/// この対応表自体は主に「次に割り当てる名前の衝突判定」に使い、生存セッションの名前を覚えておく。
final class MTTmuxSession: ObservableObject {
  static let shared = MTTmuxSession()

  private static let storeKey = "MTSessionTmuxNames"

  /// セッションキー → そのセッションが使っている tmux セッション名
  @Published private(set) var names: [UUID: String]

  private init() {
    let stored = UserDefaults.standard.dictionary(forKey: Self.storeKey) as? [String: String] ?? [:]
    names = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
      UUID(uuidString: key).map { ($0, value) }
    })
  }

  func name(for key: UUID?) -> String? {
    guard let key else { return nil }
    return names[key]
  }

  func store(_ name: String, for key: UUID) {
    guard names[key] != name else { return }
    names[key] = name
    persist()
  }

  func clear(for key: UUID) {
    guard names[key] != nil else { return }
    names.removeValue(forKey: key)
    persist()
  }

  private func persist() {
    UserDefaults.standard.set(
      Dictionary(uniqueKeysWithValues: names.map { ($0.key.uuidString, $0.value) }),
      forKey: Self.storeKey)
  }

  /// 新規接続に割り当てる tmux セッション名を決める。
  /// `base`（ホスト設定の名前。既定 "main"）から始め、同じ alias の生存セッションが
  /// 既に使っている名前は避けて `base-2` `base-3` … と採番する。
  func assignName(forAlias alias: String, base: String) -> String {
    // 同じ alias に紐づく生存セッションが使っている tmux 名を集める
    let sameHostKeys = MTHostContext.shared.aliases
      .filter { $0.value == alias }
      .map { $0.key }
    let used = Set(sameHostKeys.compactMap { names[$0] })

    if !used.contains(base) {
      return base
    }
    var i = 2
    while used.contains("\(base)-\(i)") {
      i += 1
    }
    return "\(base)-\(i)"
  }
}
