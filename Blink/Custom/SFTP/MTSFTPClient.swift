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

/// サーバーのホスト鍵を検証する。
///
///  1. 記録済みの指紋があればそれと照合する（従来どおり）
///  2. 初回は、SSH/Mosh 本接続（libssh）の known_hosts に同じホスト・同じ鍵種の
///     記録があればそれと照合する。SSH で信頼済みの鍵を初回信頼の裏打ちにして、
///     TOFU の「初回は無条件に信じる」窓を塞ぐ。同種の鍵が食い違えば拒否する
///  3. どこにも記録が無いときだけ TOFU（提示された鍵を記録して信頼）
///
/// `.acceptAnything()` は使わない。鍵が変わったら接続を拒否する。
/// 正当な鍵変更（サーバー再構築など）からの復旧は `reset(hostID:)`（UI から呼ぶ）。
final class MTTofuHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
  private let storageKey: String
  private let hostName: String
  private let port: Int

  /// 直近の検証失敗が「鍵の不一致」だったか。Citadel が検証エラーを別の型に包んで
  /// 伝えることがあり、呼び出し側で MTSFTPError.hostKeyChanged を取り出せるとは
  /// 限らないため、UI の「鍵を忘れて再試行」導線の表示判定に使う。
  ///
  /// 書き込みは NIO の EventLoop スレッド、読み出しは MainActor と actor から来るため
  /// ロックで守る。接続は UI から 1 本ずつ張る前提（同時に 2 本張ると後勝ちになる）。
  private static let flagLock = NSLock()
  private static var _lastFailureWasKeyMismatch = false

  private static var lastFailureWasKeyMismatch: Bool {
    get { flagLock.lock(); defer { flagLock.unlock() }; return _lastFailureWasKeyMismatch }
    set { flagLock.lock(); _lastFailureWasKeyMismatch = newValue; flagLock.unlock() }
  }

  /// 接続を始める前に呼ぶ。以前の判定を必ず捨てる。
  ///
  /// 鍵の検証に辿り着かない失敗（名前解決・タイムアウト・認証）では
  /// `validateHostKey` が呼ばれないため、ここで消さないと前回の「鍵が変わった」が
  /// 残り、無関係なエラーで「以前の鍵を忘れて再接続」を出してしまう。
  /// この導線は押すと安全性が下がるので、誤って出さない
  static func beginAttempt() {
    lastFailureWasKeyMismatch = false
  }

  init(hostID: String, hostName: String, port: Int) {
    self.storageKey = Self.storageKey(hostID: hostID)
    self.hostName = hostName
    self.port = port
  }

  private static func storageKey(hostID: String) -> String {
    "MTSFTPHostKeyFingerprint.\(hostID)"
  }

  /// 記録済みの指紋を破棄する（サーバー再構築などで鍵が正当に変わったときの復旧手段）
  static func reset(hostID: String) {
    UserDefaults.standard.removeObject(forKey: storageKey(hostID: hostID))
  }

  /// 発生したエラーが「ホスト鍵の不一致」によるものか（UI 用）
  static func isHostKeyChanged(_ error: Error) -> Bool {
    if let e = error as? MTSFTPError, case .hostKeyChanged = e { return true }
    return lastFailureWasKeyMismatch
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
        Self.lastFailureWasKeyMismatch = true
        validationCompletePromise.fail(MTSFTPError.hostKeyChanged)
      }
      return
    }

    // 初回：known_hosts（本接続の信頼）と照合してから記録する
    switch Self.knownHostsVerdict(hostName: hostName, port: port, wireKey: bytes) {
    case .match, .unknown:
      defaults.set(fingerprint, forKey: storageKey)
      validationCompletePromise.succeed(())
    case .mismatch:
      Self.lastFailureWasKeyMismatch = true
      validationCompletePromise.fail(MTSFTPError.hostKeyChanged)
    }
  }

  enum KnownHostsVerdict {
    case match     // 同じホスト・同じ鍵種で鍵が一致した
    case mismatch  // 同じホスト・同じ鍵種なのに鍵が違う
    case unknown   // 記録が無い・読めない（TOFU に委ねる）
  }

  /// known_hosts に同じホストのエントリがあるか調べる。
  /// 行形式は `host[,host…] <鍵種> <base64>`。ハッシュ化行（|1|…）と
  /// マーカー行（@…）は照合できないため読み飛ばす（unknown 扱い）。
  static func knownHostsVerdict(hostName: String, port: Int, wireKey: Data) -> KnownHostsVerdict {
    let path: String? = BlinkPaths.knownHostsFile()
    guard
      let path,
      let content = try? String(contentsOfFile: path, encoding: .utf8),
      let presentedType = keyType(ofWireKey: wireKey)
    else {
      return .unknown
    }
    // 22 番ポートは素のホスト名、それ以外は `[host]:port` 形式で記録される
    let host = hostName.lowercased()
    let targets = port == 22 ? [host] : ["[\(host)]:\(port)"]
    var sawSameType = false
    for line in content.split(whereSeparator: \.isNewline) {
      let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
      guard fields.count >= 3, !fields[0].hasPrefix("@"), !fields[0].hasPrefix("|") else { continue }
      let hosts = fields[0].lowercased().split(separator: ",").map(String.init)
      guard hosts.contains(where: { targets.contains($0) }) else { continue }
      guard fields[1] == presentedType else { continue }  // 鍵種が違うのは別の鍵（変更ではない）
      sawSameType = true
      if let blob = Data(base64Encoded: fields[2]), blob == wireKey {
        return .match
      }
    }
    return sawSameType ? .mismatch : .unknown
  }

  /// SSH wire 形式の先頭フィールド（"ssh-ed25519" 等の鍵種文字列）を取り出す
  private static func keyType(ofWireKey data: Data) -> String? {
    let bytes = [UInt8](data)
    guard bytes.count >= 4 else { return nil }
    let len = (Int(bytes[0]) << 24) | (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3])
    guard len > 0, len <= 64, bytes.count >= 4 + len else { return nil }
    return String(bytes: bytes[4 ..< 4 + len], encoding: .utf8)
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
    MTTofuHostKeyValidator.beginAttempt()
    let validator = SSHHostKeyValidator.custom(
      MTTofuHostKeyValidator(hostID: alias, hostName: hostName, port: port))

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
