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

/// コマンドライブラリ（S19、MT 移植）。よく使うコマンドを登録し、タップで端末へ
/// **改行なしで挿入**する（実行はユーザーが Enter）。お手本 MT の「コマンドライブラリ」に相当。

struct MTCommand: Identifiable, Codable, Equatable {
  var id = UUID()
  var title: String
  var command: String
}

/// コマンドライブラリの保存（UserDefaults・JSON）
final class MTCommandStore: ObservableObject {
  static let shared = MTCommandStore()
  private static let key = "MTCommandLibrary"

  @Published private(set) var commands: [MTCommand]

  private init() {
    if let data = UserDefaults.standard.data(forKey: Self.key),
       let list = try? JSONDecoder().decode([MTCommand].self, from: data) {
      commands = list
    } else {
      // 初期サンプル（空だと使い方が分かりにくいため）
      commands = [
        MTCommand(title: "tmux セッション一覧", command: "tmux ls"),
        MTCommand(title: "ディスク使用量", command: "df -h"),
        MTCommand(title: "プロセス監視", command: "htop"),
        MTCommand(title: "git 状態", command: "git status"),
      ]
    }
  }

  func add(title: String, command: String) {
    commands.append(MTCommand(title: title, command: command))
    persist()
  }

  func update(_ item: MTCommand) {
    guard let idx = commands.firstIndex(where: { $0.id == item.id }) else { return }
    commands[idx] = item
    persist()
  }

  func delete(at offsets: IndexSet) {
    commands.remove(atOffsets: offsets)
    persist()
  }

  func move(from source: IndexSet, to destination: Int) {
    commands.move(fromOffsets: source, toOffset: destination)
    persist()
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(commands) {
      UserDefaults.standard.set(data, forKey: Self.key)
    }
  }
}

struct MTCommandLibraryView: View {
  /// 端末へ改行なしで挿入する（呼び出し側で currentDevice?.receive を叩く）
  let onInsert: (String) -> Void

  @ObservedObject private var store = MTCommandStore.shared
  @ObservedObject private var themeStore = MTThemeStore.shared
  @Environment(\.dismiss) private var dismiss
  @State private var editing: MTCommand?
  @State private var showingNew = false

  private var theme: MTTheme { themeStore.currentTheme }

  var body: some View {
    NavigationView {
      List {
        Section {
          ForEach(store.commands) { item in
            Button {
              dismiss(); onInsert(item.command)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(item.title).foregroundColor(.primary)
                Text(item.command)
                  .font(MTFont.mono(12, relativeTo: .caption))
                  .foregroundColor(.secondary)
                  .lineLimit(1)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
              Button("編集") { editing = item }.tint(theme.sub.color)
            }
          }
          .onDelete { store.delete(at: $0) }
          .onMove { store.move(from: $0, to: $1) }
        } footer: {
          Text("タップで現在のセッションに挿入します（Enter は付きません）。左スワイプで編集、ドラッグで並べ替え。")
        }
      }
      .navigationTitle("コマンドライブラリ")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
        ToolbarItem(placement: .primaryAction) {
          Button { showingNew = true } label: { Image(systemName: "plus") }
        }
        ToolbarItem(placement: .navigationBarLeading) { EditButton() }
      }
      .sheet(item: $editing) { item in
        MTCommandEditor(command: item) { store.update($0) }
      }
      .sheet(isPresented: $showingNew) {
        MTCommandEditor(command: MTCommand(title: "", command: "")) {
          store.add(title: $0.title, command: $0.command)
        }
      }
    }
    .navigationViewStyle(.stack)
  }
}

/// コマンドの追加・編集フォーム
private struct MTCommandEditor: View {
  @State var command: MTCommand
  let onSave: (MTCommand) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationView {
      Form {
        Section("名前") {
          TextField("例: git 状態", text: $command.title)
        }
        Section("コマンド") {
          TextField("例: git status", text: $command.command, axis: .vertical)
            .font(MTFont.mono(14))
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
        }
      }
      .navigationTitle("コマンド")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            let t = command.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let c = command.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !c.isEmpty else { dismiss(); return }
            command.title = t.isEmpty ? c : t
            command.command = c
            onSave(command)
            dismiss()
          }
        }
      }
    }
    .navigationViewStyle(.stack)
  }
}
