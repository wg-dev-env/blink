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
import UIKit

// MARK: - モデル

struct MTTabItem: Identifiable, Equatable {
  let key: UUID
  let title: String
  /// 1 始まりの連番。iPad / Mac では ⌘1〜9 と一致する（06 §5.1）
  let index: Int
  var id: UUID { key }
}

final class MTTabBarModel: ObservableObject {
  @Published var items: [MTTabItem] = []
  @Published var currentKey: UUID? = nil
}

/// 設定の歯車メニューの中身（タブバーとサイドバーで共有）
struct MTSettingsMenu: View {
  let onSettings: () -> Void
  let onCommandBlocks: () -> Void
  let onShieldNow: () -> Void

  var body: some View {
    Button { onSettings() } label: { Label("設定", systemImage: "gearshape") }
    Button { onCommandBlocks() } label: { Label("コマンド履歴", systemImage: "list.bullet.rectangle") }
    Button { onShieldNow() } label: { Label("今すぐ伏せる", systemImage: "eye.slash") }
  }
}

// MARK: - タブバー（06 §5.1）

struct MTTabBarView: View {
  @ObservedObject var model: MTTabBarModel
  @ObservedObject private var themeStore = MTThemeStore.shared
  @ObservedObject private var stateCenter = MTSessionStateCenter.shared
  @ObservedObject private var sessionsStore = MTSessionsStore.shared

  let onSelect: (UUID) -> Void
  let onNew: () -> Void
  let onList: () -> Void
  let onRename: (UUID) -> Void
  let onClose: (UUID) -> Void
  let onSettings: () -> Void
  let onCommandBlocks: () -> Void
  let onShieldNow: () -> Void
  /// タブバーに歯車を出すか（サイドバーがある iPad / Mac では false）
  var showSettings: Bool = true

  private var theme: MTTheme { themeStore.currentTheme }

  var body: some View {
    HStack(spacing: 6) {
      // 件数ボタン（タップでセッション一覧。一覧画面は S7、それまでは既存 HUD 表示）
      Button(action: onList) {
        Text("\(model.items.count)")
          .font(MTFont.mono(13, .medium))
          .foregroundColor(theme.sub.color)
          .frame(width: 44, height: 36)
          .background(RoundedRectangle(cornerRadius: 10).fill(theme.raised.color))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text("セッション一覧。\(model.items.count) 件"))

      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            // 非表示セッション（06 §6.2）はタブにも出さない
            ForEach(model.items.filter { !sessionsStore.hiddenKeys.contains($0.key) }) { item in
              MTTabView(
                item: item,
                state: stateCenter.state(for: item.key),
                isActive: item.key == model.currentKey,
                theme: theme,
                onSelect: { onSelect(item.key) },
                onClose: { onClose(item.key) }
              )
              // ダブルタップでも名前を変えられる（長押しメニューに加えて）
              .simultaneousGesture(TapGesture(count: 2).onEnded { onRename(item.key) })
              .contextMenu {
                Button("名前を変更") { onRename(item.key) }
                Button("隠す") { sessionsStore.hide(item.key) }
                Button("閉じる", role: .destructive) { onClose(item.key) }
              }
              .id(item.key)
            }
          }
        }
        .onChange(of: model.currentKey) { _, key in
          guard let key else { return }
          withAnimation { proxy.scrollTo(key, anchor: .center) }
        }
      }

      // 設定（06 §6.5）とコマンド履歴（07 #05）。
      // サイドバーがある iPad / Mac では、歯車はサイドバー側に出すのでここには出さない
      if showSettings {
        Menu {
          MTSettingsMenu(onSettings: onSettings, onCommandBlocks: onCommandBlocks, onShieldNow: onShieldNow)
        } label: {
          Image(systemName: "gearshape")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(theme.sub.color)
            .frame(width: 44, height: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.raised.color))
        }
        .accessibilityLabel(Text("設定とコマンド履歴"))
      }

      // 新規タブ
      Button(action: onNew) {
        Image(systemName: "plus")
          .font(.system(size: 15, weight: .medium))
          .foregroundColor(theme.sub.color)
          .frame(width: 44, height: 36)
          .background(RoundedRectangle(cornerRadius: 10).fill(theme.raised.color))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text("新規セッション"))
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .frame(height: 44)
    .frame(maxWidth: .infinity)
    .background(theme.bg.color.ignoresSafeArea(edges: .horizontal))
  }
}

/// タブ 1 枚。高さ 36pt・角丸 10pt・左右 12pt・文字 13pt、左に状態の点（色＋形）。
private struct MTTabView: View {
  let item: MTTabItem
  let state: MTSessionState
  let isActive: Bool
  let theme: MTTheme
  let onSelect: () -> Void
  let onClose: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      // 選択（onTapGesture でなく Button にして「×」との競合を避ける）
      Button(action: onSelect) {
        HStack(spacing: 6) {
          MTStateBadge(state: state, theme: theme)
          // 連番（iPad / Mac は ⌘1〜9 と対応）
          Text("\(item.index)")
            .font(MTFont.mono(11, .medium))
            .foregroundColor(isActive ? theme.ok.color : theme.muted.color)
          Text(item.title)
            .font(MTFont.ui(13, isActive ? .medium : .regular))
            .foregroundColor(isActive ? theme.text.color : theme.sub.color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 10)
        .padding(.trailing, isActive ? 0 : 10)
        .frame(height: 36)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text("\(item.index) 番 \(item.title)。\(state.label)"))
      .accessibilityAddTraits(isActive ? .isSelected : [])

      if isActive {
        // アクティブタブの「×」= このセッションを閉じる（06 §5.1）
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(theme.muted.color)
            // 見た目は小さく、当たり判定は 44pt 相当に広げる
            .frame(width: 32, height: 36)
            .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(item.title) を閉じる"))
      }
    }
    .frame(minWidth: 110, maxWidth: 200)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isActive ? theme.okBg.color : theme.surface.color)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(isActive ? theme.ok.color : theme.line.color, lineWidth: 1)
    )
  }
}

/// 状態バッジ。色だけでなく形でも区別する（06 §4）。
struct MTStateBadge: View {
  let state: MTSessionState
  let theme: MTTheme

  var body: some View {
    Group {
      switch state {
      case .connected:
        Circle().fill(theme.ok.color).frame(width: 8, height: 8)
      case .reconnecting:
        Circle().stroke(theme.warn.color, lineWidth: 2).frame(width: 8, height: 8)
      case .held:
        RoundedRectangle(cornerRadius: 1).fill(theme.bad.color).frame(width: 8, height: 2)
      case .restored:
        RoundedRectangle(cornerRadius: 2).fill(theme.restore.color).frame(width: 8, height: 8)
      }
    }
    .frame(width: 10, height: 10)
  }
}

// MARK: - UIKit ホスト（SpaceController から使う）

final class MTTabBarHost: UIViewController {
  static let height: CGFloat = 64  // タブ 44（36pt + 上下 4pt）+ ライフライン 20

  /// サイドバー（MTSidebarView）と共有する（SpaceController の update で両方へ反映される）
  let model = MTTabBarModel()

  /// タブバー＋直下のライフライン（06 §2）
  private struct ChromeView: View {
    @ObservedObject var model: MTTabBarModel
    let onSelect: (UUID) -> Void
    let onNew: () -> Void
    let onList: () -> Void
    let onRename: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onSettings: () -> Void
    let onCommandBlocks: () -> Void
    let onShieldNow: () -> Void
    let showSettings: Bool

    var body: some View {
      VStack(spacing: 0) {
        MTTabBarView(model: model, onSelect: onSelect, onNew: onNew, onList: onList,
                     onRename: onRename, onClose: onClose, onSettings: onSettings,
                     onCommandBlocks: onCommandBlocks, onShieldNow: onShieldNow,
                     showSettings: showSettings)
        MTLifelineView()
          .frame(height: 20)
      }
    }
  }

  init(onSelect: @escaping (UUID) -> Void,
       onNew: @escaping () -> Void,
       onList: @escaping () -> Void,
       onRename: @escaping (UUID) -> Void,
       onClose: @escaping (UUID) -> Void,
       onSettings: @escaping () -> Void,
       onCommandBlocks: @escaping () -> Void,
       onShieldNow: @escaping () -> Void,
       showSettings: Bool = true) {
    super.init(nibName: nil, bundle: nil)
    let hosting = UIHostingController(
      rootView: ChromeView(model: model, onSelect: onSelect, onNew: onNew, onList: onList,
                           onRename: onRename, onClose: onClose, onSettings: onSettings,
                     onCommandBlocks: onCommandBlocks, onShieldNow: onShieldNow,
                     showSettings: showSettings))
    addChild(hosting)
    hosting.view.backgroundColor = .clear
    hosting.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(hosting.view)
    NSLayoutConstraint.activate([
      hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
      hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    hosting.didMove(toParent: self)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func update(items: [MTTabItem], current: UUID?) {
    if model.items != items { model.items = items }
    if model.currentKey != current { model.currentKey = current }
  }
}
