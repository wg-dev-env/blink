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

import Citadel
import Foundation

/// サーバー側の tmux セッションを明示的に終了する（削除機能）。
///
/// セッションを「閉じる／隠す」は iOS 側の接続を切るだけで、再接続・Handoff の
/// ためにサーバーの tmux セッションは意図的に残す設計（MTTmuxSession 参照）。
/// しかし不要になったセッションがサーバーに蓄積し続けるため、ユーザーが明示的に
/// 削除できる手段としてこの actor を用意する。
///
/// 接続経路は MTTmuxLister / MTSFTPClient と同じ使い捨て Citadel 接続。退行リスクを
/// 避けるため既存 Mosh/SSH（libssh）の本接続とは独立して一瞬だけ張る。
enum MTTmuxKiller {
  /// サーバーで `tmux kill-session -t <name>` を実行し、**本当に消えたか確認する**。
  ///
  /// 戻り値 `true` は「終了後にそのセッションが存在しない（＝成功。元々無かった場合も含む）」。
  /// `false` は「接続はできたがセッションがまだ残っている」。接続自体に失敗した場合
  /// （鍵未設定・ホスト不明・ネットワーク断）は throw する。
  ///
  /// 以前は `tmux kill-session ... 2>/dev/null` を `try?` で捨てていたため、名前が
  /// サーバー上の実名と一致せず "can't find session" になっても成功扱いになり、
  /// 「削除したのにサーバーに tmux が残る」症状の原因が一切表に出なかった。ここでは
  /// kill 直後に `has-session` で生死を確認し、結果を呼び出し側へ返す。
  static func kill(alias: String, sessionName: String) async throws -> Bool {
    let client = try await MTTmuxLister.connectClient(alias: alias)
    defer { Task { try? await client.close() } }
    // 名前は採番カウンタ由来（main-1 等）で記号を含まない前提だが、念のため
    // シングルクォートで囲み、含まれ得る ' を '\'' でエスケープする。
    let quoted = "'" + sessionName.replacingOccurrences(of: "'", with: "'\\''") + "'"
    // kill → has-session を 1 本のスクリプトで実行する。終了コードは必ず 0 に正規化
    // して（Citadel の非ゼロ終了による throw を避ける）、最後に GONE / ALIVE を echo する。
    let script = "tmux kill-session -t \(quoted) >/dev/null 2>&1; "
      + "if tmux has-session -t \(quoted) 2>/dev/null; then echo ALIVE; else echo GONE; fi"
    let buffer = try await client.executeCommand(script)
    let out = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) ?? ""
    return out.contains("GONE")
  }
}
