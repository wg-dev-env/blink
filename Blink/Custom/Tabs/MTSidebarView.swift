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

import SwiftUI

/// iPad / Mac の左サイドバー（06 §7、幅 264pt、⌘⇧S で開閉）。
/// セッション一覧と接続先（ホスト）をまとめて見せる。iPad と Mac で共通実装。
struct MTSidebarView: View {
  @ObservedObject var model: MTTabBarModel
  let onSelect: (UUID) -> Void
  let onConnect: (String, MTConnectKind) -> Void
  let onNewConnection: () -> Void
  let onRename: (UUID) -> Void
  let onClose: (UUID) -> Void
  let onSettings: () -> Void
  let onCommandBlocks: () -> Void
  let onShieldNow: () -> Void

  @ObservedObject private var stateCenter = MTSessionStateCenter.shared
  @ObservedObject private var sessionsStore = MTSessionsStore.shared
  @ObservedObject private var themeStore = MTThemeStore.shared
  @StateObject private var hosts = MTHostsModel()

  static let width: CGFloat = 264

  private var theme: MTTheme { themeStore.currentTheme }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // ヘッダ: アプリ名と設定への入口
      HStack {
        Text("Iroha")
          .font(MTFont.ui(15, .bold))
          .foregroundColor(theme.text.color)
        Spacer()
        Menu {
          MTSettingsMenu(onSettings: onSettings, onCommandBlocks: onCommandBlocks, onShieldNow: onShieldNow)
        } label: {
          Image(systemName: "gearshape")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(theme.sub.color)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("設定とコマンド履歴"))
      }
      .padding(.horizontal, 12)
      .padding(.top, 6)

      List {
        Section {
          ForEach(model.items.filter { !sessionsStore.hiddenKeys.contains($0.key) }) { item in
            sessionRow(item)
          }
        } header: {
          Text("セッション")
            .font(MTFont.ui(11, .medium))
            .foregroundColor(theme.muted.color)
        }

        Section {
          if hosts.items.isEmpty {
            Text("ホスト未登録")
              .font(MTFont.ui(12))
              .foregroundColor(theme.muted.color)
          } else {
            ForEach(hosts.items) { host in
              hostRow(host)
            }
          }
          Label("接続を追加", systemImage: "plus")
            .font(MTFont.ui(13, .medium))
            .foregroundColor(theme.accent.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { onNewConnection() }
            .accessibilityAddTraits(.isButton)
        } header: {
          Text("接続先")
            .font(MTFont.ui(11, .medium))
            .foregroundColor(theme.muted.color)
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
    }
    .frame(width: Self.width)
    .background(theme.surface.color)
    .overlay(alignment: .trailing) {
      Rectangle().fill(theme.line.color).frame(width: 1)
    }
    .onAppear { hosts.reload() }
  }

  @ViewBuilder
  private func sessionRow(_ item: MTTabItem) -> some View {
    let state = stateCenter.state(for: item.key)
    let isActive = item.key == model.currentKey

    // List 内の Button(.plain) はタップに反応しないことがあるため、
    // 行全体を contentShape + onTapGesture でタップ可能にする
    HStack(spacing: 8) {
      MTStateBadge(state: state, theme: theme)
      Text("\(item.index)")
        .font(MTFont.mono(11, .medium))
        .foregroundColor(isActive ? theme.ok.color : theme.muted.color)
      Text(item.title)
        .font(MTFont.ui(13, isActive ? .medium : .regular))
        .foregroundColor(isActive ? theme.text.color : theme.sub.color)
        .lineLimit(1)
      Spacer()
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .onTapGesture { onSelect(item.key) }
    .simultaneousGesture(TapGesture(count: 2).onEnded { onRename(item.key) })
    .listRowBackground(isActive ? theme.okBg.color : Color.clear)
    .contextMenu {
      Button("名前を変更") { onRename(item.key) }
      Button("隠す") { sessionsStore.hide(item.key) }
      Button("閉じる", role: .destructive) { onClose(item.key) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("\(item.title)。\(state.label)"))
    .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
  }

  @ViewBuilder
  private func hostRow(_ host: MTHostItem) -> some View {
    HStack(spacing: 8) {
      Text(host.initials)
        .font(MTFont.mono(10, .medium))
        .foregroundColor(theme.bg.color)
        .frame(width: 24, height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme.accent.color))
      VStack(alignment: .leading, spacing: 1) {
        Text(host.alias)
          .font(MTFont.ui(13))
          .foregroundColor(theme.sub.color)
          .lineLimit(1)
        Text(host.display)
          .font(MTFont.mono(10))
          .foregroundColor(theme.muted.color)
          .lineLimit(1)
      }
      Spacer()
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .onTapGesture { onConnect(host.alias, .mosh) }
    .contextMenu {
      Button(MTConnectKind.mosh.label) { onConnect(host.alias, .mosh) }
      Button(MTConnectKind.ssh.label) { onConnect(host.alias, .ssh) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(Text("\(host.alias) に Mosh で接続"))
  }
}
