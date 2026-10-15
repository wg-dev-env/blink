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
import Foundation

/// デバイスをまたぐセッション（07 #07 Handoff）。
///
/// mosh / ssh の接続そのものは渡せない（ローカルのプロセスとソケットのため）。
/// 渡すのは「どのホストへ、どの tmux セッションで繋いでいたか」で、受け側は
/// 同じホストへ接続し直して同じ tmux セッションにアタッチする。
/// tmux 自動アタッチと組み合わせると、実質「同じ画面の続き」になる。
///
/// iCloud のエンタイトルメントは不要（Handoff は NSUserActivity だけで成立する）。
/// 条件は、両方の端末が同じ Apple Account でサインインしていることと、
/// Bluetooth / Wi-Fi が有効なこと。
enum MTHandoff {
  /// Info.plist の NSUserActivityTypes に登録した型
  static let activityType = "com.wgdevenv.moshterm.session"

  private enum Key {
    static let alias = "alias"
    static let tmux = "tmux"
    static let title = "title"
  }

  /// 今のセッションを他の端末へ広告する
  static func makeActivity(alias: String, title: String?) -> NSUserActivity? {
    guard !alias.isEmpty else { return nil }
    let host = BKHosts.withHost(alias)
    let activity = NSUserActivity(activityType: activityType)
    activity.title = title ?? alias
    activity.isEligibleForHandoff = true
    activity.isEligibleForSearch = false
    activity.isEligibleForPublicIndexing = false

    var info: [String: Any] = [Key.alias: alias]
    if host?.tmuxAutoAttach?.boolValue == true {
      info[Key.tmux] = TmuxAutoAttach.sanitizedSessionName(host?.tmuxSessionName)
    }
    if let title { info[Key.title] = title }
    activity.userInfo = info
    activity.requiredUserInfoKeys = [Key.alias]
    return activity
  }

  struct Payload {
    let alias: String
    let tmux: String?
    let title: String?

    /// 受け側で実行するコマンド。tmux 名が来ていればそれを明示して引き継ぐ
    var command: String {
      guard let tmux, !tmux.isEmpty else { return "mosh \(alias)" }
      return "mosh \(alias) -- tmux new -A -s \(tmux)"
    }
  }

  /// 受け取った activity を解釈する
  static func payload(from activity: NSUserActivity) -> Payload? {
    guard activity.activityType == activityType,
          let info = activity.userInfo,
          let alias = info[Key.alias] as? String, !alias.isEmpty else { return nil }
    return Payload(
      alias: alias,
      tmux: info[Key.tmux] as? String,
      title: info[Key.title] as? String)
  }
}
