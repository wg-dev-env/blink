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
import NIOSSH

/// SFTP ファイル転送（S16、[[10_寛容ライセンス部品の活用調査]]§2）。
/// 既存の SSH/Mosh 接続（libssh）はそのままに、ファイル閲覧・DL/UL だけを
/// 純 Swift の Citadel で新規に提供する（退行リスクのない純増機能）。

/// 一覧の 1 エントリ
struct MTSFTPEntry: Identifiable, Hashable {
  var id: String { name }
  let name: String
  let isDirectory: Bool
  let size: UInt64?
  let modified: Date?
}

enum MTSFTPError: LocalizedError {
  case hostNotFound
  case noAuth(String)
  case unsupportedKey(String)
  case hostKeyChanged
  case notConnected

  var errorDescription: String? {
    switch self {
    case .hostNotFound: return "接続先が見つかりません。"
    case .noAuth(let m): return "認証情報がありません：\(m)"
    case .unsupportedKey(let t): return "未対応の鍵形式です（\(t)）。ed25519 か RSA を使ってください。"
    case .hostKeyChanged: return "サーバーのホスト鍵が以前と変わっています。接続を中止しました。"
    case .notConnected: return "接続していません。"
    }
  }
}

/// サーバーのホスト鍵を初回に記録し、以後は一致を検証する（TOFU）。
/// `.acceptAnything()` は使わない。鍵が変わったら接続を拒否する。
final class MTTofuHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
  private let storageKey: String

  init(hostID: String) {
    self.storageKey = "MTSFTPHostKeyFingerprint.\(hostID)"
  }

  func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
    var buffer = ByteBufferAllocator().buffer(capacity: 256)
    _ = hostKey.write(to: &buffer)
    let bytes = Data(buffer.readableBytesView)
    let fingerprint = Data(SHA256.hash(data: bytes)).map { String(format: "%02x", $0) }.joined()

    let defaults = UserDefaults.standard
    if let stored = defaults.string(forKey: storageKey) {
      if stored == fingerprint {
        validationCompletePromise.succeed(())
      } else {
        validationCompletePromise.fail(MTSFTPError.hostKeyChanged)
      }
    } else {
      // 初回：この鍵を信頼として記録（Trust On First Use）
      defaults.set(fingerprint, forKey: storageKey)
      validationCompletePromise.succeed(())
    }
  }
}

/// 1 ホストへの SFTP セッション。接続・一覧・DL/UL を async で提供する。
actor MTSFTPSession {
  private var client: SSHClient?
  private var sftp: SFTPClient?
  let alias: String

  init(alias: String) {
    self.alias = alias
  }

  /// BKHosts の設定（ホスト名・ポート・ユーザー・鍵／パスワード）で接続する。
  func connect() async throws {
    guard let host = BKHosts.withHost(alias) else { throw MTSFTPError.hostNotFound }
    let hostName = host.hostName ?? alias
    let port = host.port?.intValue ?? 22
    let user = (host.user?.isEmpty == false ? host.user : nil) ?? NSUserName()

    let auth = try Self.authMethod(for: host, user: user)
    let validator = SSHHostKeyValidator.custom(MTTofuHostKeyValidator(hostID: alias))

    let client = try await SSHClient.connect(
      host: hostName,
      port: port,
      authenticationMethod: auth,
      hostKeyValidator: validator,
      reconnect: .never
    )
    self.client = client
    self.sftp = try await client.openSFTP()
  }

  /// BKHosts から Citadel の認証方式を組み立てる（鍵優先、無ければパスワード）。
  private static func authMethod(for host: BKHosts, user: String) throws -> SSHAuthenticationMethod {
    if let keyName = host.key, !keyName.isEmpty,
       let pubkey = BKPubKey.withID(keyName),
       let priv = pubkey.loadPrivateKey(), !priv.isEmpty {
      let type = (try? SSHKeyDetection.detectPrivateKeyType(from: priv))?.rawValue ?? ""
      switch type {
      case "ssh-ed25519":
        let key = try Curve25519.Signing.PrivateKey(sshEd25519: priv)
        return .ed25519(username: user, privateKey: key)
      case "ssh-rsa":
        let key = try Insecure.RSA.PrivateKey(sshRsa: priv)
        return .rsa(username: user, privateKey: key)
      default:
        // ecdsa 等は v1 未対応（ネットワーク経路は確立済みなので将来追加）
        throw MTSFTPError.unsupportedKey(type.isEmpty ? "不明" : type)
      }
    }
    if let password = host.password, !password.isEmpty {
      return .passwordBased(username: user, password: password)
    }
    throw MTSFTPError.noAuth("鍵もパスワードも設定されていません")
  }

  /// ディレクトリ一覧。`.`/`..` は除外し、ディレクトリを先に名前順で返す。
  func list(_ path: String) async throws -> [MTSFTPEntry] {
    guard let sftp else { throw MTSFTPError.notConnected }
    let names = try await sftp.listDirectory(atPath: path)
    var entries: [MTSFTPEntry] = []
    for name in names {
      for item in name.components where item.filename != "." && item.filename != ".." {
        let perms = item.attributes.permissions
        let isDir: Bool
        if let perms { isDir = (perms & 0o170000) == 0o040000 }
        else { isDir = item.longname.first == "d" }
        entries.append(MTSFTPEntry(
          name: item.filename,
          isDirectory: isDir,
          size: item.attributes.size,
          modified: item.attributes.accessModificationTime?.modificationTime))
      }
    }
    return entries.sorted {
      $0.isDirectory != $1.isDirectory ? $0.isDirectory
        : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  /// ファイルをダウンロードして Data で返す。
  func download(_ path: String) async throws -> Data {
    guard let sftp else { throw MTSFTPError.notConnected }
    return try await sftp.withFile(filePath: path, flags: .read) { file in
      var buffer = try await file.readAll()
      return buffer.readData(length: buffer.readableBytes) ?? Data()
    }
  }

  /// Data をアップロード（既存は上書き）。
  func upload(_ data: Data, to path: String) async throws {
    guard let sftp else { throw MTSFTPError.notConnected }
    try await sftp.withFile(filePath: path, flags: [.write, .create, .truncate]) { file in
      try await file.write(ByteBuffer(data: data))
    }
  }

  func disconnect() async {
    try? await sftp?.close()
    try? await client?.close()
    sftp = nil
    client = nil
  }
}
