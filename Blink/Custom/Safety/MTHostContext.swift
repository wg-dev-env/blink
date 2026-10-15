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

/// 「このセッションはどのホストに繋がっているか」の対応表。
/// Blink 本体はこれを持たない（MCPParams.initialCommand は永続化されない）ため、
/// 接続コマンドから alias を取り出して自前で保持する。額縁・危険コマンド・
/// 圏外ドラフトの 3 機能が参照する（07 #02/#03/#04）。
final class MTHostContext: ObservableObject {
  static let shared = MTHostContext()

  private static let storeKey = "MTSessionHostAliases"

  /// セッションキー → ホストの alias
  @Published private(set) var aliases: [UUID: String]

  private init() {
    let stored = UserDefaults.standard.dictionary(forKey: Self.storeKey) as? [String: String] ?? [:]
    aliases = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
      UUID(uuidString: key).map { ($0, value) }
    })
  }

  func alias(for key: UUID?) -> String? {
    guard let key else { return nil }
    return aliases[key]
  }

  func bind(alias: String, to key: UUID) {
    guard !alias.isEmpty, aliases[key] != alias else { return }
    aliases[key] = alias
    persist()
  }

  func clear(for key: UUID) {
    guard aliases[key] != nil else { return }
    aliases.removeValue(forKey: key)
    persist()
  }

  private func persist() {
    UserDefaults.standard.set(
      Dictionary(uniqueKeysWithValues: aliases.map { ($0.key.uuidString, $0.value) }),
      forKey: Self.storeKey)
  }

  // MARK: - 便利アクセサ

  func environment(for key: UUID?) -> MTEnvironment {
    MTSafety.environment(forAlias: alias(for: key))
  }

  /// 接続コマンド（"mosh macmini" / "ssh macmini -p 22" 等）から alias を取り出す
  static func parseAlias(fromCommand command: String) -> String? {
    let words = command.split(separator: " ").map(String.init)
    guard words.count >= 2, ["mosh", "ssh", "ssh2", "mosh1"].contains(words[0]) else { return nil }
    // オプションを読み飛ばして最初の非オプション語を alias とみなす
    for word in words.dropFirst() where !word.hasPrefix("-") {
      return word
    }
    return nil
  }
}
