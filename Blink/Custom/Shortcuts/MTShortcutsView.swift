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

/// キーボードショートカット一覧（チートシート）。⌘/ で開く。
/// 実際に有効な設定（KBTracker のアクティブ KBConfig）を読み、記号＋日本語の説明で見せる。
struct MTShortcutsView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var themeStore = MTThemeStore.shared

  private var theme: MTTheme { themeStore.currentTheme }

  /// 表示用の 1 行
  private struct Item: Identifiable {
    let id: String
    let keys: String      // 例: ⌘⇧N
    let label: String     // 日本語の説明
  }

  /// 表示用セクション（グループ名 → 行）
  private struct DisplayGroup: Identifiable {
    let id: String
    let title: String
    let items: [Item]
  }

  var body: some View {
    NavigationView {
      List {
        ForEach(groups) { group in
          Section(group.title) {
            ForEach(group.items) { item in
              HStack(spacing: 12) {
                Text(item.label)
                  .font(MTFont.ui(15))
                  .foregroundColor(.primary)
                Spacer(minLength: 12)
                Text(item.keys)
                  .font(MTFont.mono(14, .medium))
                  .foregroundColor(theme.accent.color)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 3)
                  .background(RoundedRectangle(cornerRadius: 6).fill(theme.raised.color))
              }
              .padding(.vertical, 2)
              .accessibilityElement(children: .combine)
            }
          }
        }
      }
      .navigationTitle("キーボードショートカット")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
        }
      }
    }
    .navigationViewStyle(.stack)
  }

  // MARK: データ組み立て

  /// アクティブなショートカットを読み、既知のものは日本語化・グループ分けして返す。
  private var groups: [DisplayGroup] {
    let shortcuts = KBTracker.shared.loadConfig().shortcuts.filter { !$0.isCleared }

    // 1 つの Command に複数キーが割り当たることがある（例: タブ切替の [ と ←）。
    // コマンドごとに記号をまとめる。
    var keysByCommand: [Command: [String]] = [:]
    var orderSeen: [Command] = []
    for s in shortcuts {
      guard case .command(let cmd) = s.action else { continue }
      if keysByCommand[cmd] == nil { orderSeen.append(cmd) }
      keysByCommand[cmd, default: []].append(s.description)
    }

    func makeItem(_ cmd: Command) -> Item? {
      guard let keys = keysByCommand[cmd], let label = Self.labels[cmd] else { return nil }
      return Item(id: cmd.rawValue, keys: keys.joined(separator: " / "), label: label)
    }

    var result: [DisplayGroup] = []
    for section in Self.sections {
      let items = section.commands.compactMap { makeItem($0) }
      if !items.isEmpty {
        result.append(DisplayGroup(id: section.title, title: section.title, items: items))
      }
    }
    // ラベル未登録のコマンドも取りこぼさない（英語名のまま「その他」へ）
    let known = Set(Self.sections.flatMap { $0.commands })
    let others: [Item] = orderSeen.filter { !known.contains($0) }.compactMap { cmd -> Item? in
      guard let keys = keysByCommand[cmd] else { return nil }
      let label = Self.labels[cmd] ?? cmd.rawValue
      return Item(id: cmd.rawValue, keys: keys.joined(separator: " / "), label: label)
    }
    if !others.isEmpty {
      result.append(DisplayGroup(id: "その他", title: "その他", items: others))
    }
    return result
  }

  // MARK: 日本語ラベルとグループ定義（お手本 MT のショートカットに準拠）

  private struct SectionDef { let title: String; let commands: [Command] }

  private static let sections: [SectionDef] = [
    SectionDef(title: "接続・セッション", commands: [
      .connectSheetShow, .tmuxPickerShow, .sftpShow, .disconnectCurrent, .sessionHide,
    ]),
    SectionDef(title: "ウィンドウ・タブ", commands: [
      .windowNew, .windowClose, .windowFocusOther, .tabNew, .tabClose, .tabNext, .tabPrev,
      .tabMoveToOtherWindow, .sidebarToggle,
      .tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8, .tab9,
    ]),
    SectionDef(title: "表示・配色・文字サイズ", commands: [
      .paletteCycle, .shieldNow, .zoomIn, .zoomOut, .zoomReset,
    ]),
    SectionDef(title: "編集・入力", commands: [
      .clipboardCopy, .clipboardCopyRaw, .clipboardPaste,
      .commandBlocksShow, .commandLibraryShow, .snippetsShow, .scratchShow,
    ]),
    SectionDef(title: "設定・ヘルプ", commands: [
      .configShow, .shortcutsHelpShow,
    ]),
  ]

  private static let labels: [Command: String] = [
    .connectSheetShow:    "接続先を開く",
    .tmuxPickerShow:      "tmux セッションを開く",
    .sftpShow:            "ファイル（SFTP）を開く",
    .disconnectCurrent:   "この接続を切断",
    .sessionHide:         "このセッションを隠す",
    .windowNew:           "新しいウィンドウ",
    .windowClose:         "ウィンドウを閉じる",
    .windowFocusOther:    "別ウィンドウへ移動",
    .tabNew:              "新しいタブ",
    .tabClose:            "タブを閉じる",
    .tabNext:             "次のタブ",
    .tabPrev:             "前のタブ",
    .tabMoveToOtherWindow: "タブを別ウィンドウへ",
    .sidebarToggle:       "サイドバーの表示切替",
    .tab1:                "タブ 1 へ",
    .tab2:                "タブ 2 へ",
    .tab3:                "タブ 3 へ",
    .tab4:                "タブ 4 へ",
    .tab5:                "タブ 5 へ",
    .tab6:                "タブ 6 へ",
    .tab7:                "タブ 7 へ",
    .tab8:                "タブ 8 へ",
    .tab9:                "タブ 9 へ",
    .paletteCycle:        "配色を切り替え",
    .shieldNow:           "今すぐ画面を伏せる",
    .zoomIn:              "文字を大きく",
    .zoomOut:             "文字を小さく",
    .zoomReset:           "文字サイズをリセット",
    .clipboardCopy:       "コピー",
    .clipboardCopyRaw:    "そのままコピー",
    .clipboardPaste:      "ペースト",
    .commandBlocksShow:   "コマンド履歴を開く",
    .commandLibraryShow:  "コマンドライブラリを開く",
    .snippetsShow:        "スニペットを開く",
    .scratchShow:         "スクラッチを開く",
    .configShow:          "設定を開く",
    .shortcutsHelpShow:   "ショートカット一覧（この画面）",
  ]
}
