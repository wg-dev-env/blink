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
///
/// `@MainActor` は必須。`killSessions` / `load` は `await` を含む async で、isolation が
/// 無いと最初の `await` でメインスレッドを離れる（SE-0338）。離れたまま `@State` を書き、
/// さらに `onWillKill` / `onKilled` 経由で SpaceController の `_mtCloseSession` →
/// `UIPageViewController.setViewControllers` までバックグラウンドで呼んでしまうため、
/// SwiftUI の AttributeGraph と UIKit の両方が壊れる。同じ並行処理を持つ
/// `MTSFTPModel`（MTSFTPBrowserView.swift）や `SpaceController._mtDeleteSession` は
/// 既にメイン固定になっているので、それに揃える。
@MainActor
struct MTTmuxPickerView: View {
  let alias: String
  /// 既存セッションへアタッチ（複数可）
  let onAttach: ([String]) -> Void
  /// 新規セッションを作成
  let onNew: () -> Void
  /// サーバーの tmux セッションを kill する**直前**に、その名前を通知する。
  /// 呼び出し側は、同名を焼き込んだ開きっぱなしのローカルタブ（Mosh/SSH）を先に
  /// 終了させ、`tmux new -A -s` による再接続・作り直しの主体を消しておく。
  ///
  /// ゾンビ復活の本命対策：アタッチ中の Mosh タブが生きたままサーバー側のセッションを
  /// kill すると、セッション消滅を「回線断」と誤認した Mosh が自動再接続し、初期コマンド
  /// `-- tmux new -A -s <name>` を再実行して削除直後の同名を作り直してしまう。kill の
  /// 前にローカルを畳んでおけば、作り直す主体がいなくなる（SpaceController 側で処理）。
  var onWillKill: (String) -> Void = { _ in }
  /// サーバーの tmux セッションを削除（kill）できたあとにも、その名前を通知する。
  /// onWillKill の取りこぼし（名前不一致で畳めなかったタブ等）への二重の掃除。
  var onKilled: (String) -> Void = { _ in }

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var themeStore = MTThemeStore.shared

  @State private var sessions: [MTTmuxSessionInfo] = []
  @State private var loading = true
  @State private var selecting = false
  @State private var selected: Set<String> = []
  /// 削除確認の対象セッション名（nil のときは非表示）。単体スワイプは1件、一括は複数。
  @State private var pendingKill: [String]? = nil
  /// 削除中のセッション名（二重実行・連打防止）
  @State private var killing: Set<String> = []
  /// 削除失敗の通知文（nil のときは非表示）
  @State private var killError: String? = nil

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
                // フルスワイプで誤って kill しないよう無効化（必ずボタン＋確認を踏ませる）
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                  Button(role: .destructive) {
                    pendingKill = [s.name]
                  } label: {
                    Label("削除", systemImage: "trash")
                  }
                  .disabled(killing.contains(s.name))
                }
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
              // 選択モードでは、選んだセッションを「削除（サーバーごと終了）」か「開く（アタッチ）」。
              // 溜まった tmux セッションの掃除は、ここか各行の左スワイプ削除で行う。
              HStack(spacing: 16) {
                Button(role: .destructive) {
                  pendingKill = sessions.map(\.name).filter { selected.contains($0) }
                } label: {
                  Label("削除（\(selected.count)）", systemImage: "trash")
                }
                .disabled(selected.isEmpty)
                Button("開く（\(selected.count)）") {
                  let names = sessions.map(\.name).filter { selected.contains($0) }
                  guard !names.isEmpty else { selecting = false; return }
                  dismiss(); onAttach(names)
                }
                .disabled(selected.isEmpty)
              }
            } else {
              Button("選択") { selecting = true }
            }
          }
        }
      }
    }
    // iPad（regular 幅）で NavigationView が split 表示になり、一覧が左カラムに寄って
    // 右半分が空白になるのを防ぐ。他の MT シート（MTSessionsView 等）と揃える。
    .navigationViewStyle(.stack)
    .task { await load() }
    .alert("tmux セッションを削除", isPresented: Binding(
      get: { pendingKill != nil },
      set: { if !$0 { pendingKill = nil } }
    ), presenting: pendingKill) { names in
      Button("削除", role: .destructive) {
        pendingKill = nil
        Task { await killSessions(names) }
      }
      Button("キャンセル", role: .cancel) { pendingKill = nil }
    } message: { names in
      if names.count == 1 {
        Text("「\(names[0])」をサーバーの tmux セッションごと終了します。元に戻せません。")
      } else {
        Text("選択した \(names.count) 件をサーバーの tmux セッションごと終了します。元に戻せません。")
      }
    }
    .alert("削除に失敗", isPresented: Binding(
      get: { killError != nil },
      set: { if !$0 { killError = nil } }
    )) {
      Button("OK", role: .cancel) { killError = nil }
    } message: {
      Text(killError ?? "")
    }
  }

  /// 指定したセッションをサーバーの tmux ごと終了する（破壊的）。
  /// 既存のタブ削除と同じ `MTTmuxKiller.kill` を使う。成功したものは一覧から外す。
  private func killSessions(_ names: [String]) async {
    var failed: [String] = []
    for name in names {
      killing.insert(name)
      defer { killing.remove(name) }
      // kill の前に、この名前を焼き込んだローカルタブ（アタッチ中の Mosh/SSH）を先に畳む。
      // 畳まずにサーバーを kill すると、Mosh が消滅を回線断と誤認して自動再接続し、
      // 初期コマンドの `tmux new -A -s <name>` を再実行して削除直後の同名を作り直す
      // （＝ゾンビ復活）。先にローカルを落とし、再接続の猶予（0.4 秒）を置いてから kill する。
      onWillKill(name)
      try? await Task.sleep(nanoseconds: 400_000_000)
      do {
        let gone = try await MTTmuxKiller.kill(alias: alias, sessionName: name)
        if gone {
          sessions.removeAll { $0.name == name }
          selected.remove(name)
          // 同名を焼き込んだ開きっぱなしのタブを閉じて、再接続・復元での再生成を防ぐ
          onKilled(name)
        } else {
          failed.append(name)
        }
      } catch {
        failed.append(name)
      }
    }
    if !failed.isEmpty {
      killError = "終了できませんでした（サーバーに残っています）：\(failed.joined(separator: ", "))"
    }
    if sessions.isEmpty { selecting = false }
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
