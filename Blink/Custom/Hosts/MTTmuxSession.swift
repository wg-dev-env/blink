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
  /// 新規接続に振る番号の採番カウンタ。一度使った番号は二度と再利用しない（永続）。
  private static let counterKey = "MTSessionTmuxCounter"

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
  ///
  /// `base`（ホスト設定の名前。既定 "main"）に、**一度も使っていない番号**を付けて
  /// `base-1` `base-2` … を返す。素の `base` は決して返さない。
  ///
  /// なぜ「使い回さない」か:
  /// 以前は「今追跡しているセッションが使っていない最小の名前」を返していたため、
  /// タブを閉じると名前が空き、次の新規接続で同じ名前を再利用していた。ところが
  /// 閉じても**サーバー側の tmux セッションは生きたまま**なので、`tmux new -A -s <名前>`
  /// が生き残った同名セッションへ再アタッチし、「閉じたタブの内容が新規タブに写る
  /// （鏡写し）」不具合になっていた。番号を単調に増やして二度と再利用しないことで、
  /// 新規接続は必ずサーバーに存在しない名前になり、独立したまっさらなセッションになる。
  /// 再開（切れない）は接続コマンドに同名が焼き込まれているので従来どおり戻れる。
  ///
  /// カウンタは永続し、アプリ再起動後も続きから採番する（`forAlias` は将来の拡張用。
  /// 現状は全ホスト共通のカウンタで一意性を保証する）。
  func assignName(forAlias alias: String, base: String) -> String {
    return "\(base)-\(nextCounter())"
  }

  /// 次の採番番号を返す（1 から始まり、呼ぶたびに +1 して永続）。
  private func nextCounter() -> Int {
    let next = UserDefaults.standard.integer(forKey: Self.counterKey) + 1
    UserDefaults.standard.set(next, forKey: Self.counterKey)
    return next
  }
}
