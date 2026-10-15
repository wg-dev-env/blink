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
import SwiftUI
import UIKit

// MARK: - データ

/// 接続方式。`mosh <alias>` / `ssh <alias>` の 1 語で BKHosts の設定
/// （鍵・ポート・mosh 設定・tmux 自動アタッチ）が全て効く。
/// SSH は自動再接続フック（MCPSession の reconnectionCommand）と整合する `ssh` を使う。
enum MTConnectKind {
  case mosh
  case ssh

  var command: String {
    switch self {
    case .mosh: return "mosh"
    case .ssh: return "ssh"
    }
  }

  var label: String {
    switch self {
    case .mosh: return "Mosh で接続"
    case .ssh: return "SSH で接続"
    }
  }
}

/// ホストカード 1 枚分の表示データ（06 §6.3）
struct MTHostItem: Identifiable {
  let alias: String
  let display: String   // user@hostName:port
  let tmuxName: String? // tmux 自動アタッチが有効ならセッション名
  let hasKey: Bool
  let hasProxyJump: Bool

  var id: String { alias }
  var initials: String { String(alias.prefix(2)).uppercased() }
}

/// BKHosts の読み込みと検索絞り込み
final class MTHostsModel: ObservableObject {
  /// ホストの追加・編集後に全モデル（サイドバー・接続シート）へ再読込を知らせる
  static let changedNotification = Notification.Name("MTHostsChanged")

  @Published private(set) var items: [MTHostItem] = []

  init() {
    reload()
    NotificationCenter.default.addObserver(
      self, selector: #selector(handleChanged),
      name: Self.changedNotification, object: nil)
  }

  @objc private func handleChanged() {
    reload()
  }

  static func notifyChanged() {
    NotificationCenter.default.post(name: changedNotification, object: nil)
  }

  func reload() {
    let hosts = BKHosts.allHosts() ?? []
    items = hosts.compactMap { host -> MTHostItem? in
      guard let alias = host.host, !alias.isEmpty else { return nil }
      let hostName = (host.hostName?.isEmpty == false) ? host.hostName! : alias
      let user = host.user ?? ""
      let portValue = host.port?.intValue
      let port = (portValue == nil || portValue == 22) ? "" : ":\(portValue!)"
      let tmux = host.tmuxAutoAttach?.boolValue == true
        ? TmuxAutoAttach.sanitizedSessionName(host.tmuxSessionName)
        : nil
      return MTHostItem(
        alias: alias,
        display: (user.isEmpty ? "" : "\(user)@") + hostName + port,
        tmuxName: tmux,
        hasKey: host.key?.isEmpty == false,
        hasProxyJump: host.proxyJump?.isEmpty == false
      )
    }
    .sorted { $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending }
  }

  func filtered(by query: String) -> [MTHostItem] {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return items }
    return items.filter {
      $0.alias.localizedCaseInsensitiveContains(q) || $0.display.localizedCaseInsensitiveContains(q)
    }
  }
}

// MARK: - 接続先シート（06 §6.3 を踏襲）

struct MTHostsView: View {
  let onConnect: (String, MTConnectKind) -> Void
  let onLocalShell: () -> Void
  let onClose: () -> Void

  @EnvironmentObject private var nav: Nav
  @ObservedObject private var themeStore = MTThemeStore.shared
  @StateObject private var model = MTHostsModel()
  @State private var query = ""

  private var theme: MTTheme { themeStore.currentTheme }

  var body: some View {
    List {
      if model.items.isEmpty {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text("接続先がまだありません")
              .font(MTFont.ui(15, .medium))
            Text("ホスト名・ユーザー・鍵・tmux 自動アタッチを登録すると、タップひとつで Mosh 接続できます。")
              .font(MTFont.ui(13))
              .foregroundColor(.secondary)
            Label("最初のホストを登録", systemImage: "plus")
              .font(MTFont.ui(15, .medium))
              .foregroundColor(theme.accent.color)
              .padding(.top, 4)
              .contentShape(Rectangle())
              .onTapGesture { editHost(nil) }
          }
          .padding(.vertical, 6)
        }
      } else {
        Section {
          TextField("名前・ホストで検索", text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)

          ForEach(model.filtered(by: query)) { item in
            hostRow(item)
          }
        } header: {
          Text("ホスト")
        } footer: {
          Text("タップで Mosh 接続。長押しで SSH 接続・編集。")
        }

        Section {
          Label("新規ホスト", systemImage: "plus")
            .foregroundColor(theme.accent.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { editHost(nil) }
        }
      }

      Section {
        Label("ローカルシェル", systemImage: "terminal")
          .foregroundColor(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
          .contentShape(Rectangle())
          .onTapGesture { onLocalShell() }
          .accessibilityHint(Text("接続せずに新しいタブを開きます"))
      }
    }
    .navigationTitle("接続先")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Button("閉じる", action: onClose)
      }
    }
    .onAppear { model.reload() }
  }

  // MARK: 行

  @ViewBuilder
  private func hostRow(_ item: MTHostItem) -> some View {
    // List 内の Button はタップに反応しないことがあるため onTapGesture を使う
    HStack(spacing: 10) {
      // 2 文字イニシャルの角丸（06 §6.3）
      Text(item.initials)
        .font(MTFont.mono(13, .medium))
        .foregroundColor(theme.bg.color)
        .frame(width: 34, height: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.accent.color))

      VStack(alignment: .leading, spacing: 2) {
        Text(item.alias)
          .font(MTFont.ui(15, .medium))
          .foregroundColor(.primary)
          .lineLimit(1)
        Text(item.display)
          .font(MTFont.mono(12))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }

      Spacer()

      HStack(spacing: 4) {
        tag("mosh", color: theme.ok.color)
        if let tmux = item.tmuxName {
          tag("tmux:\(tmux)", color: theme.accent.color)
        }
        if item.hasKey {
          tag("鍵", color: theme.sub.color)
        }
        if item.hasProxyJump {
          tag("jump", color: theme.sub.color)
        }
      }
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .onTapGesture { onConnect(item.alias, .mosh) }
    .contextMenu {
      Button(MTConnectKind.mosh.label) { onConnect(item.alias, .mosh) }
      Button(MTConnectKind.ssh.label) { onConnect(item.alias, .ssh) }
      Button("編集") { editHost(BKHosts.withHost(item.alias)) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("\(item.alias)、\(item.display)。Mosh で接続"))
  }

  private func tag(_ text: String, color: Color) -> some View {
    Text(text)
      .font(MTFont.mono(10))
      .foregroundColor(color)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
      .lineLimit(1)
  }

  // MARK: 登録・編集（既存 HostView を流用）

  private func editHost(_ host: BKHosts?) {
    // サイドバー側の一覧も更新されるよう、保存後は通知で全モデルを再読込する
    let view = HostView(host: host, reloadList: { MTHostsModel.notifyChanged() })
      .environmentObject(nav)
    let vc = UIHostingController(rootView: view)
    vc.overrideUserInterfaceStyle = MTThemeStore.shared.overrideInterfaceStyle ?? .unspecified
    nav.navController.pushViewController(vc, animated: true)
  }
}
