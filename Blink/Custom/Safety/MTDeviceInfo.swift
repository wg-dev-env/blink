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
import UIKit

/// この端末の名前。ローカルシェルのタブ名・プロンプトに使う。
/// iOS 16 以降は OS の制限で機種名（"iPhone" 等）になることがある。
///
/// `UIDevice.current.name` / `.model` はメインスレッド専用 API だが、`localPrompt` は
/// MCP のシリアルコマンドキュー（`MCPSession.m` の `mcp.command.queue`）から呼ばれる
/// ＝ローカルシェルのタブを開く、`exit` でリモートから戻る、復元で初期コマンドが走る、
/// のたびにバックグラウンドで UIKit を叩いていた。そのため値は一度だけ読んでキャッシュし、
/// 以降はどのスレッドからでもそのキャッシュを返す。
@objc public class MTDeviceInfo: NSObject {
  /// 端末名のキャッシュ。Swift の `static let` は一度だけ・スレッドセーフに初期化される。
  /// 初期化がメイン以外から始まった場合だけメインへ同期で寄せる（コマンドキューに対して
  /// `dispatch_sync` するコードは無いのでデッドロックしない）。通常は起動時の
  /// `primeOnMainThread()` で既に温まっているため、この分岐は通らない。
  private static let cachedName: String = {
    if Thread.isMainThread {
      return _readNameOnMainThread()
    }
    return DispatchQueue.main.sync { _readNameOnMainThread() }
  }()

  private static func _readNameOnMainThread() -> String {
    let n = UIDevice.current.name
    return n.isEmpty ? UIDevice.current.model : n
  }

  /// 起動時にメインスレッドから一度呼び、キャッシュを温めておく（AppDelegate から呼ぶ）。
  @objc public static func primeOnMainThread() {
    _ = cachedName
  }

  @objc public static var name: String { cachedName }

  /// ローカルシェルのプロンプト（例「iPhone ~ 」）
  @objc public static var localPrompt: String {
    "\(name) ~ "
  }
}
