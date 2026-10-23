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
import Citadel
import Crypto
import Foundation
import NIOCore

/// 接続時の tmux セッションピッカー（S17）のためのサーバー側セッション一覧取得。
///
/// 既存 SSH/Mosh（libssh）の本接続とは別に、Citadel で一瞬だけ制御用接続を張り
/// `tmux ls` を実行して一覧を得る（SFTP と同じ思想・退行リスクなし）。鍵・ホスト鍵・
/// BKHosts 解決は SFTP（MTSFTPClient）と同じ経路。

/// tmux セッション 1 件
struct MTTmuxSessionInfo: Identifiable, Hashable, Sendable {
  var id: String { name }
  let name: String
  let windows: Int
}

/// 一覧取得の結果。
///
/// 以前は失敗も `[]` で返していたため、遅い回線や到達しないホストで
/// 「既存の tmux セッションはありません」と表示され、**サーバーに既存セッションが
/// あるのに新規作成へ誘導**してしまっていた（元の画面に戻れない）。
/// 「本当に無い」と「取れなかった」を型で区別する。
enum MTTmuxListResult: Sendable {
  case sessions([MTTmuxSessionInfo])
  case failed(reason: String)
}

/// 一覧取得が時間内に終わらなかった
struct MTTmuxListTimeout: LocalizedError {
  var errorDescription: String? { "時間内に応答がありませんでした。" }
}

/// 接続の共有エラー（鍵未対応・認証なし・ホスト不明）
enum MTSSHError: LocalizedError {
  case hostNotFound
  case noAuth(String)
  case unsupportedKey(String)

  var errorDescription: String? {
    switch self {
    case .hostNotFound: return "接続先が見つかりません。"
    case .noAuth(let m): return "認証情報がありません：\(m)"
    case .unsupportedKey(let t): return "未対応の鍵形式です（\(t)）。ed25519 か RSA を使ってください。"
    }
  }
}

/// サーバーの tmux セッション一覧を取得する（制御用の使い捨て Citadel 接続）。
actor MTTmuxLister {
  let alias: String

  init(alias: String) { self.alias = alias }

  /// 一覧取得の既定のタイムアウト（秒）。遅い回線でシートが固まらないための上限。
  static let defaultTimeout: Double = 8

  /// `tmux ls` を実行してセッション一覧を返す。
  ///
  /// 接続・実行に失敗した場合や、`timeout` 秒以内に終わらなかった場合は
  /// `.failed(reason:)` を返す。セッションが 1 つも無い（tmux 未起動など）ときだけ
  /// `.sessions([])` になる。呼び出し側はこの 2 つを区別して表示すること。
  func list(timeout: Double = MTTmuxLister.defaultTimeout) async -> MTTmuxListResult {
    let alias = self.alias
    do {
      let sessions = try await Self.withTimeout(timeout) {
        try await Self.fetch(alias: alias)
      }
      return .sessions(sessions)
    } catch {
      return .failed(reason: error.localizedDescription)
    }
  }

  /// 実際の取得処理（接続 → `tmux ls` → パース）
  private static func fetch(alias: String) async throws -> [MTTmuxSessionInfo] {
    let client = try await connectClient(alias: alias)
    defer { Task { try? await client.close() } }
    // `#{...}` は tmux のフォーマット。名前にタブ・改行は入らない前提で name<TAB>windows
    let cmd = "tmux ls -F '#{session_name}\t#{session_windows}' 2>/dev/null"
    let buffer = try await client.executeCommand(cmd)
    let text = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) ?? ""
    var result: [MTTmuxSessionInfo] = []
    for line in text.split(whereSeparator: \.isNewline) {
      let cols = line.split(separator: "\t", maxSplits: 1).map(String.init)
      guard let name = cols.first, !name.isEmpty else { continue }
      let windows = cols.count > 1 ? Int(cols[1].trimmingCharacters(in: .whitespaces)) ?? 1 : 1
      result.append(MTTmuxSessionInfo(name: name, windows: windows))
    }
    return result
  }

  /// 処理とタイマーを競走させ、先に終わった方を採る。
  /// Citadel の接続自体はキャンセルに応じないことがあるが、待っている側は必ず
  /// `timeout` 秒で解放される（取り残したタスクはバックグラウンドで畳まれる）。
  private static func withTimeout<T: Sendable>(
    _ seconds: Double,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw MTTmuxListTimeout()
      }
      guard let first = try await group.next() else {
        throw MTTmuxListTimeout()
      }
      group.cancelAll()
      return first
    }
  }

  /// BKHosts の設定で Citadel の SSHClient を確立する（SFTP と同じ鍵/ホスト鍵解決）。
  static func connectClient(alias: String) async throws -> SSHClient {
    guard let host = BKHosts.withHost(alias) else { throw MTSSHError.hostNotFound }
    let hostName = host.hostName ?? alias
    let port = host.port?.intValue ?? 22
    let user = (host.user?.isEmpty == false ? host.user : nil) ?? NSUserName()
    let auth = try authMethod(for: host, user: user)
    // ホスト鍵は SFTP と同じ TOFU 検証（MTTofuHostKeyValidator は MTSFTPClient.swift で定義）
    let validator = SSHHostKeyValidator.custom(MTTofuHostKeyValidator(hostID: alias))
    return try await SSHClient.connect(
      host: hostName, port: port,
      authenticationMethod: auth, hostKeyValidator: validator, reconnect: .never)
  }

  /// BKHosts から Citadel の認証方式を組み立てる（鍵優先、無ければパスワード）。
  /// ※ MTSFTPSession.authMethod と同等（将来一本化）。ecdsa 等は v1 未対応。
  static func authMethod(for host: BKHosts, user: String) throws -> SSHAuthenticationMethod {
    if let keyName = host.key, !keyName.isEmpty,
       let pubkey = BKPubKey.withID(keyName),
       let priv = pubkey.loadPrivateKey(), !priv.isEmpty {
      let type = (try? SSHKeyDetection.detectPrivateKeyType(from: priv))?.rawValue ?? ""
      switch type {
      case "ssh-ed25519":
        return .ed25519(username: user, privateKey: try Curve25519.Signing.PrivateKey(sshEd25519: priv))
      case "ssh-rsa":
        return .rsa(username: user, privateKey: try Insecure.RSA.PrivateKey(sshRsa: priv))
      default:
        throw MTSSHError.unsupportedKey(type.isEmpty ? "不明" : type)
      }
    }
    if let password = host.password, !password.isEmpty {
      return .passwordBased(username: user, password: password)
    }
    throw MTSSHError.noAuth("鍵もパスワードも設定されていません")
  }
}
