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
  /// サーバーで `tmux kill-session -t <name>` を実行する。
  ///
  /// 既に存在しないセッション名でもエラーにはせず成功扱いにする（目的は「消えていること」）。
  /// 接続自体に失敗した場合（鍵未設定・ホスト不明・ネットワーク断）は throw する。
  static func kill(alias: String, sessionName: String) async throws {
    let client = try await MTTmuxLister.connectClient(alias: alias)
    defer { Task { try? await client.close() } }
    // 名前は採番カウンタ由来（main-1 等）で記号を含まない前提だが、念のため
    // シングルクォートで囲み、含まれ得る ' を '\'' でエスケープする。
    let quoted = "'" + sessionName.replacingOccurrences(of: "'", with: "'\\''") + "'"
    // セッションが無い場合の "can't find session" は stderr へ出るだけなので握りつぶす。
    _ = try? await client.executeCommand("tmux kill-session -t \(quoted) 2>/dev/null")
  }
}
