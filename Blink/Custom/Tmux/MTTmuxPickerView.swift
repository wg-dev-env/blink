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

/// 接続時の tmux セッションピッカー（S17）。お手本 MT に準拠。
/// 既存セッションを選んでアタッチ／新規作成／すべて開く／複数選択。Esc（閉じる）で接続中止。
struct MTTmuxPickerView: View {
  let alias: String
  /// 既存セッションへアタッチ（複数可）
  let onAttach: ([String]) -> Void
  /// 新規セッションを作成
  let onNew: () -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var themeStore = MTThemeStore.shared

  @State private var sessions: [MTTmuxSessionInfo] = []
  @State private var loading = true
  @State private var selecting = false
  @State private var selected: Set<String> = []

  private var theme: MTTheme { themeStore.currentTheme }

  var body: some View {
    NavigationView {
      List {
        Section {
          Button {
            dismiss(); onNew()
          } label: {
            Label("新しいセッションを作成", systemImage: "plus.circle")
          }
          if !sessions.isEmpty {
            Button {
              dismiss(); onAttach(sessions.map(\.name))
            } label: {
              Label("すべて開く（\(sessions.count)）", systemImage: "square.on.square")
            }
          }
        } footer: {
          if loading {
            Text("サーバーの tmux セッションを取得中…")
          } else if sessions.isEmpty {
            Text("既存の tmux セッションはありません。新規作成で接続します。")
          } else {
            Text("セッションを選んでアタッチします。「選択」で複数まとめて開けます。")
          }
        }

        if !sessions.isEmpty {
          Section("既存のセッション") {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, s in
              row(index: index, session: s)
            }
          }
        }
      }
      .overlay { if loading { ProgressView() } }
      .navigationTitle("tmux セッション")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("接続を中止") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          if !sessions.isEmpty {
            if selecting {
              Button("開く（\(selected.count)）") {
                let names = sessions.map(\.name).filter { selected.contains($0) }
                guard !names.isEmpty else { selecting = false; return }
                dismiss(); onAttach(names)
              }
              .disabled(selected.isEmpty)
            } else {
              Button("選択") { selecting = true }
            }
          }
        }
      }
    }
    .task { await load() }
  }

  @ViewBuilder
  private func row(index: Int, session: MTTmuxSessionInfo) -> some View {
    let isChecked = selected.contains(session.name)
    HStack(spacing: 12) {
      Text("\(index + 1)")
        .font(MTFont.mono(13))
        .foregroundColor(theme.accent.color)
        .frame(width: 20, alignment: .trailing)
      VStack(alignment: .leading, spacing: 2) {
        Text(session.name).foregroundColor(.primary)
        Text("\(session.windows) window").font(MTFont.ui(12, relativeTo: .caption)).foregroundColor(.secondary)
      }
      Spacer()
      if selecting {
        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
          .foregroundColor(isChecked ? theme.accent.color : .secondary)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      if selecting {
        if isChecked { selected.remove(session.name) } else { selected.insert(session.name) }
      } else {
        dismiss(); onAttach([session.name])
      }
    }
    .onLongPressGesture {
      if !selecting { selecting = true }
      selected.insert(session.name)
    }
  }

  private func load() async {
    let list = await MTTmuxLister(alias: alias).list()
    sessions = list
    loading = false
  }
}
