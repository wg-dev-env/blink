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

// MARK: - スクラブで出す読み取り専用の画面（07 #01）

struct MTScrubOverlayView: View {
  @ObservedObject private var history = MTScreenHistory.shared
  @ObservedObject private var themeStore = MTThemeStore.shared

  private var theme: MTTheme { themeStore.currentTheme }

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "H:mm:ss"
    return f
  }()

  var body: some View {
    if let snapshot = history.scrubbing {
      VStack(spacing: 0) {
        // 見出し: いつの画面か
        HStack(spacing: 8) {
          Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: 12, weight: .medium))
          Text("\(Self.timeFormatter.string(from: snapshot.date)) の画面")
            .font(MTFont.ui(13, .medium))
          Text(snapshot.reason)
            .font(MTFont.mono(11))
            .foregroundColor(theme.muted.color)
          Spacer()
          Button {
            UIPasteboard.general.string = snapshot.text
          } label: {
            Label("コピー", systemImage: "doc.on.doc")
              .font(MTFont.ui(12, .medium))
          }
          .buttonStyle(.plain)
          .foregroundColor(theme.accent.color)
          Button {
            MTScreenHistory.shared.scrubbing = nil
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 16))
              .foregroundColor(theme.muted.color)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("今の画面に戻る"))
        }
        .foregroundColor(theme.sub.color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.raised.color)

        // 本文（読み取り専用）
        ScrollView {
          Text(snapshot.text)
            .font(MTFont.mono(12))
            .foregroundColor(theme.term.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(10)
        }
        .background(theme.bg.color)
      }
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(theme.accent.color, lineWidth: 2)
      )
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .padding(10)
      .transition(.opacity)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(Text("\(Self.timeFormatter.string(from: snapshot.date)) の画面。読み取り専用"))
    }
  }
}

// MARK: - コマンドブロックの一覧（07 #05）

/// 出力をコマンド単位でコピーできる一覧。範囲選択を不要にするのが目的。
struct MTCommandBlocksView: View {
  let sessionKey: UUID?

  @ObservedObject private var store = MTCommandBlockStore.shared
  @ObservedObject private var themeStore = MTThemeStore.shared
  @Environment(\.dismiss) private var dismiss

  private var theme: MTTheme { themeStore.currentTheme }

  private var blocks: [MTCommandBlock] {
    guard let sessionKey else { return [] }
    return store.blocks(for: sessionKey).reversed()
  }

  var body: some View {
    NavigationView {
      Group {
        if blocks.isEmpty {
          emptyState
        } else {
          List {
            ForEach(blocks) { block in
              row(block)
            }
          }
        }
      }
      .navigationTitle("コマンド履歴")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("閉じる") { dismiss() }
        }
      }
    }
    .navigationViewStyle(.stack)
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("まだ記録がありません")
        .font(MTFont.ui(15, .medium))
      Text("コマンドごとの出力をまとめるには、接続先のシェルに「シェル統合」を入れます。入れると、コマンド・終了コード・所要時間が並び、出力をワンタップでコピーできます。")
        .font(MTFont.ui(13))
        .foregroundColor(.secondary)

      Text("~/.zshrc に追記する例")
        .font(MTFont.ui(12, .medium))
        .foregroundColor(.secondary)
        .padding(.top, 4)
      Text(Self.zshSnippet)
        .font(MTFont.mono(11))
        .foregroundColor(theme.term.color)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.bg.color))

      Button {
        UIPasteboard.general.string = Self.zshSnippet
      } label: {
        Label("この設定をコピー", systemImage: "doc.on.doc")
          .font(MTFont.ui(13, .medium))
      }
      .buttonStyle(.plain)
      .foregroundColor(theme.accent.color)
      Spacer()
    }
    .padding(20)
  }

  @ViewBuilder
  private func row(_ block: MTCommandBlock) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Circle()
          .fill(block.succeeded ? theme.ok.color : theme.bad.color)
          .frame(width: 7, height: 7)
        Text(block.command.isEmpty ? "(コマンド不明)" : block.command)
          .font(MTFont.mono(13, .medium))
          .foregroundColor(.primary)
          .lineLimit(2)
        Spacer()
        if !block.succeeded {
          Text("終了 \(block.exitCode)")
            .font(MTFont.mono(11))
            .foregroundColor(theme.bad.color)
        }
        Text(block.durationLabel)
          .font(MTFont.mono(11))
          .foregroundColor(.secondary)
      }

      if !block.output.isEmpty {
        Text(block.output)
          .font(MTFont.mono(11))
          .foregroundColor(.secondary)
          .lineLimit(4)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack(spacing: 12) {
        Button {
          UIPasteboard.general.string = block.output
        } label: {
          Label("出力をコピー", systemImage: "doc.on.doc")
            .font(MTFont.ui(12, .medium))
        }
        .buttonStyle(.plain)
        .foregroundColor(theme.accent.color)

        Button {
          UIPasteboard.general.string = "$ \(block.command)\n\(block.output)"
        } label: {
          Label("コマンドごと", systemImage: "doc.on.doc.fill")
            .font(MTFont.ui(12, .medium))
        }
        .buttonStyle(.plain)
        .foregroundColor(theme.sub.color)
      }
      .padding(.top, 2)
    }
    .padding(.vertical, 4)
    .listRowBackground(block.succeeded ? Color.clear : theme.bad.color.opacity(0.07))
  }

  /// シェル統合の最小スニペット（OSC 133 のマークを出す）
  static let zshSnippet = """
  # Iroha Terminal: コマンドブロック用のシェル統合
  precmd()  { printf "\\033]133;A\\007" }
  preexec() { printf "\\033]133;C\\007" }
  _iroha_d(){ printf "\\033]133;D;%s\\007" "$?" }
  precmd_functions+=(_iroha_d)
  """
}
