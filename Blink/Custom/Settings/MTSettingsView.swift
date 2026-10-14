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

/// MoshTerm の設定画面（06 §6.5）。
/// 既存の Blink 設定と併存し、該当する既存画面へはここからも入れる。
/// AI / エージェントの項目は作らない（要件）。
struct MTSettingsView: View {
  @EnvironmentObject private var nav: Nav
  @ObservedObject private var themeStore = MTThemeStore.shared

  private var theme: MTTheme { themeStore.selectedTheme ?? MTTheme.all[0] }

  var body: some View {
    List {
      // 1. プレビューカード（選択中テーマ・diff・三言語）
      Section {
        MTSettingsPreviewCard(theme: theme, diff: themeStore.diffColors)
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
      }

      // 2–3. 配色・外観
      Section("外観") {
        pushRow("配色・外観モード・差分の配色", icon: "paintpalette") { MTAppearanceView() }
        pushRow("フォントとスタイル", icon: "textformat") { StyleCustomizationView() }
        pushRow("画面表示", icon: "display") { DisplaySettingsView() }
      }

      // 4. 入力
      Section("入力") {
        pushRow("キーボード", icon: "keyboard") { KBConfigView(config: KBTracker.shared.loadConfig()) }
        HStack {
          Label("言語", systemImage: "character.ja")
          Spacer()
          Text("システムのキーボードに従う")
            .foregroundColor(.secondary)
        }
      }

      // 5. 同期と通知（エンタイトルメント復活まで無効）
      Section {
        HStack {
          Label("iCloud 同期", systemImage: "icloud")
          Spacer()
          Text("準備中").foregroundColor(.secondary)
        }
        HStack {
          Label("プッシュ通知", systemImage: "bell")
          Spacer()
          Text("準備中").foregroundColor(.secondary)
        }
      } header: {
        Text("同期と通知")
      } footer: {
        Text("iCloud・通知のエンタイトルメント復活後に有効になります（フェーズ C4）。")
      }

      // 6. セキュリティ
      Section {
        pushRow("認証情報（鍵と証明書）", icon: "key") { KeyListView() }
      } header: {
        Text("セキュリティ")
      } footer: {
        Text("Face ID での画面ロックは従来の設定（Auto Lock）を使用します。非表示セッションの解錠はアプリを閉じるとリセットされます。")
      }

      // 7. 情報
      Section("情報") {
        pushRow("ライセンス", icon: "doc.text") { MTLicensesView() }
        Link(destination: URL(string: "https://github.com/wg-dev-env/blink")!) {
          HStack {
            Label("ソースコード", systemImage: "chevron.left.forwardslash.chevron.right")
            Spacer()
            Image(systemName: "arrow.up.right.square").foregroundColor(.secondary)
          }
        }
      }
    }
    .navigationTitle("設定")
  }

  /// 既存の Nav（UIKit ナビゲーション）へ SwiftUI 画面を push する行
  @ViewBuilder
  private func pushRow<V: View>(_ title: String, icon: String, @ViewBuilder destination: @escaping () -> V) -> some View {
    Button {
      let vc = UIHostingController(rootView: destination().environmentObject(nav))
      nav.navController.pushViewController(vc, animated: true)
    } label: {
      HStack {
        Label(title, systemImage: icon).foregroundColor(.primary)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(Color(UIColor.tertiaryLabel))
      }
    }
  }
}

/// 選択中テーマで描くプレビューカード（diff と三言語の文字を含む。06 §6.5-1）
struct MTSettingsPreviewCard: View {
  let theme: MTTheme
  let diff: (delText: MTColor, delBg: MTColor, addText: MTColor, addBg: MTColor)

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Circle().fill(theme.ok.color).frame(width: 8, height: 8)
        Text("tmux: main · 接続中")
          .font(MTFont.mono(11))
          .foregroundColor(theme.muted.color)
        Spacer()
        Text(theme.name)
          .font(MTFont.ui(11, .medium))
          .foregroundColor(theme.sub.color)
      }
      .padding(.bottom, 2)

      Text("$ ssh home")
        .font(MTFont.mono(13))
        .foregroundColor(theme.term.color)
      Text("- old_value = 1")
        .font(MTFont.mono(13))
        .foregroundColor(diff.delText.color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(diff.delBg.color)
      Text("+ new_value = 2")
        .font(MTFont.mono(13))
        .foregroundColor(diff.addText.color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(diff.addBg.color)
      Text("Aあ漢 ABC 123 → 予測")
        .font(MTFont.mono(13))
        .foregroundColor(theme.ghost.color)
        .underline(true, color: theme.ghost.color)
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 10).fill(theme.bg.color))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line.color, lineWidth: 1))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("テーマ「\(theme.name)」のプレビュー"))
  }
}

// MARK: - ライセンス（06 §6.5-7。GPL-3.0 全文・OFL・ソース URL）

struct MTLicensesView: View {
  var body: some View {
    List {
      Section("本体") {
        NavigationLinkRow(title: "GNU GPL v3（Blink / MoshTerm）", resource: "COPYING")
      }
      Section("書体（SIL Open Font License 1.1）") {
        NavigationLinkRow(title: "IBM Plex Sans JP", resource: "OFL-IBMPlexSansJP")
        NavigationLinkRow(title: "JetBrains Mono", resource: "OFL-JetBrainsMono")
      }
      Section {
        Link("ソースコードの入手先: github.com/wg-dev-env/blink",
             destination: URL(string: "https://github.com/wg-dev-env/blink")!)
      } footer: {
        Text("このアプリは Blink Shell（Blink Mobile Shell Project）のフォークであり、GNU GPL v3 の条件で利用できます。")
      }
    }
    .navigationTitle("ライセンス")
  }

  private struct NavigationLinkRow: View {
    @EnvironmentObject private var nav: Nav
    let title: String
    let resource: String

    var body: some View {
      Button {
        let vc = UIHostingController(rootView: MTLicenseTextView(title: title, resource: resource))
        nav.navController.pushViewController(vc, animated: true)
      } label: {
        HStack {
          Text(title).foregroundColor(.primary)
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(UIColor.tertiaryLabel))
        }
      }
    }
  }
}

struct MTLicenseTextView: View {
  let title: String
  let resource: String

  private var text: String {
    guard let url = Bundle.main.url(forResource: resource, withExtension: resource == "COPYING" ? nil : "txt"),
          let content = try? String(contentsOf: url, encoding: .utf8) else {
      return "ライセンス本文が見つかりません（\(resource)）"
    }
    return content
  }

  var body: some View {
    ScrollView {
      Text(text)
        .font(MTFont.mono(11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}
