//////////////////////////////////////////////////////////////////////////////////
//
// 64_MoshTerm カスタム
//
// tmux 自動アタッチ:
// ホスト設定で有効にすると、接続時に `tmux new -A -s <セッション名>` を実行して
// サーバー側の tmux セッションへ自動アタッチする（Mosh / SSH 共通）。
// 回線断やアプリ kill 後も、再接続すれば同じ tmux セッションに戻れる。
//
// This file is part of a fork of Blink (GPL-3.0).
// 本ファイルも GPL-3.0 で提供される。
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation

public enum TmuxAutoAttach {

  public static let defaultSessionName = "main"

  /// tmux のセッション名として安全な文字だけを許可する。
  /// コマンド文字列としてシェルに渡るため、記号は英数と _ - . に限定する。
  public static func sanitizedSessionName(_ name: String?) -> String {
    guard
      let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty,
      name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ".") })
    else {
      return defaultSessionName
    }
    return name
  }

  /// ホストで自動アタッチが有効なときの接続時コマンド。無効なら nil。
  public static func command(for host: BKHosts?) -> String? {
    guard let host, host.tmuxAutoAttach?.boolValue == true else {
      return nil
    }
    return "tmux new -A -s \(sanitizedSessionName(host.tmuxSessionName))"
  }

  /// ssh_config へ注入するエントリ。
  /// 呼び出し側で sshConfigAttachment より後ろに追加すること
  /// （ssh_config は先勝ちのため、ユーザーの明示設定が優先される）。
  public static func sshConfigEntries(for host: BKHosts) -> [(String, Any)] {
    guard let command = command(for: host) else {
      return []
    }
    return [
      ("RemoteCommand", command),
      ("RequestTTY", "yes"),
    ]
  }
}
