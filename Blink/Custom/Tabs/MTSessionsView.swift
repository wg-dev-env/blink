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

import Combine
import LocalAuthentication
import SwiftUI

// MARK: - 非表示セッションの置き場（06 §6.2）

/// 非表示にしたセッションのキー集合。隠してもセッションは切らない。
final class MTSessionsStore: ObservableObject {
  static let shared = MTSessionsStore()

  private static let hiddenKey = "MTHiddenSessionKeys"

  @Published private(set) var hiddenKeys: Set<UUID>
  /// Face ID 解錠状態（アプリのプロセス中のみ有効。再起動でロックに戻る）
  @Published var unlocked = false

  private init() {
    let stored = UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []
    hiddenKeys = Set(stored.compactMap(UUID.init(uuidString:)))
  }

  func hide(_ key: UUID) {
    hiddenKeys.insert(key)
    persist()
  }

  func unhide(_ key: UUID) {
    hiddenKeys.remove(key)
    persist()
  }

  private func persist() {
    UserDefaults.standard.set(hiddenKeys.map(\.uuidString), forKey: Self.hiddenKey)
  }

  /// Face ID（非搭載時はパスコード）で解錠する
  func authenticate() {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return }
    context.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "非表示のセッションを表示します") { [weak self] ok, _ in
      DispatchQueue.main.async {
        if ok { self?.unlocked = true }
      }
    }
  }
}

// MARK: - セッション一覧（06 §6.2）

struct MTSessionsView: View {
  let items: [MTTabItem]
  let currentKey: UUID?
  let onSelect: (UUID) -> Void
  let onNew: () -> Void

  @ObservedObject private var stateCenter = MTSessionStateCenter.shared
  @ObservedObject private var sessionsStore = MTSessionsStore.shared
  @ObservedObject private var themeStore = MTThemeStore.shared
  @Environment(\.dismiss) private var dismiss

  private var theme: MTTheme { themeStore.currentTheme }

  private var visibleItems: [MTTabItem] {
    items.filter { !sessionsStore.hiddenKeys.contains($0.key) }
  }

  private var hiddenItems: [MTTabItem] {
    items.filter { sessionsStore.hiddenKeys.contains($0.key) }
  }

  var body: some View {
    NavigationView {
      List {
        // 集計 3 つ（接続中 / 再接続中 / 保持・切断）
        Section {
          statsRow
        }

        Section {
          ForEach(visibleItems) { item in
            row(for: item, concealed: false)
              .swipeActions(edge: .trailing) {
                Button("隠す") {
                  sessionsStore.hide(item.key)
                }
                .tint(theme.muted.color)
              }
          }
        }

        if !hiddenItems.isEmpty {
          Section {
            if sessionsStore.unlocked {
              ForEach(hiddenItems) { item in
                row(for: item, concealed: false)
                  .swipeActions(edge: .trailing) {
                    Button("再表示") {
                      sessionsStore.unhide(item.key)
                    }
                    .tint(theme.ok.color)
                  }
              }
            } else {
              Button {
                sessionsStore.authenticate()
              } label: {
                HStack {
                  Image(systemName: "faceid")
                  Text("Face ID で表示")
                  Spacer()
                }
                .foregroundColor(theme.accent.color)
                .padding(.vertical, 6)
              }
            }
          } header: {
            Text("非表示のセッション · \(hiddenItems.count)")
          }
        }
      }
      .navigationTitle("セッション")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            dismiss()
            onNew()
          } label: {
            Label("新規", systemImage: "plus")
          }
        }
      }
    }
    .navigationViewStyle(.stack)
  }

  // MARK: 集計

  private var statsRow: some View {
    let keys = items.map(\.key)
    let connected = keys.filter { [.connected, .restored].contains(stateCenter.state(for: $0)) }.count
    let reconnecting = keys.filter { stateCenter.state(for: $0) == .reconnecting }.count
    let held = keys.filter { stateCenter.state(for: $0) == .held }.count

    return HStack(spacing: 0) {
      stat(label: "接続中", count: connected, color: theme.ok.color)
      stat(label: "再接続中", count: reconnecting, color: theme.warn.color)
      stat(label: "保持・切断", count: held, color: theme.bad.color)
    }
    .padding(.vertical, 4)
  }

  private func stat(label: String, count: Int, color: Color) -> some View {
    VStack(spacing: 2) {
      Text("\(count)")
        .font(MTFont.mono(20, .medium))
        .foregroundColor(color)
      Text(label)
        .font(MTFont.ui(11))
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: 行

  @ViewBuilder
  private func row(for item: MTTabItem, concealed: Bool) -> some View {
    let state = stateCenter.state(for: item.key)
    let timeline = stateCenter.timeline(for: item.key)

    Button {
      dismiss()
      onSelect(item.key)
    } label: {
      HStack(spacing: 10) {
        MTStateBadge(state: state, theme: theme)
        VStack(alignment: .leading, spacing: 2) {
          Text(concealed ? "●●●●●" : item.title)
            .font(MTFont.ui(15, item.key == currentKey ? .medium : .regular))
            .foregroundColor(.primary)
            .lineLimit(1)
          Text("開始から \(MTLifelineView.duration(Date().timeIntervalSince(timeline.start))) · 回線切替 \(timeline.switchCount)")
            .font(MTFont.ui(12))
            .foregroundColor(.secondary)
        }
        Spacer()
        Text(state.label)
          .font(MTFont.ui(11, .medium))
          .foregroundColor(pillColor(state))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Capsule().stroke(pillColor(state), lineWidth: 1))
      }
      .padding(.vertical, 2)
    }
    .accessibilityLabel(Text("\(concealed ? "非表示のセッション" : item.title)。\(state.label)"))
  }

  private func pillColor(_ state: MTSessionState) -> Color {
    switch state {
    case .connected: return theme.ok.color
    case .reconnecting: return theme.warn.color
    case .held: return theme.bad.color
    case .restored: return theme.restore.color
    }
  }
}
