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

/// 設定 › 診断。クラッシュ・ハングの記録を見て、共有シートで書き出す。
/// 記録はアプリ内にだけ置き、外部へは送信しない。
struct MTDiagnosticsView: View {
  @State private var entries: [MTDiagnosticEntry] = []
  @State private var confirmingClear = false

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "M月d日 HH:mm:ss"
    return f
  }()

  var body: some View {
    List {
      if entries.isEmpty {
        Section {
          Text("記録はありません。")
            .foregroundColor(.secondary)
        } footer: {
          Text("アプリが落ちた・固まったときに、その記録がここに残ります。記録は端末の中にだけ保存され、どこへも送信しません。")
        }
      } else {
        Section {
          ForEach(entries) { entry in
            NavigationLink {
              MTDiagnosticDetailView(entry: entry)
            } label: {
              row(entry)
            }
          }
        } footer: {
          Text("開いて右上から書き出せます。コールスタックはシンボル化されていないので、開発側で dSYM と突き合わせて解決します。")
        }

        Section {
          Button(role: .destructive) {
            confirmingClear = true
          } label: {
            Text("すべて削除")
          }
        }
      }

      #if BLINK_PUBLISHING_OPTION_DEVELOPER
      Section {
        Button(role: .destructive) {
          _ = MTCrashReporter.debugRaiseTestException()
        } label: {
          Label("テスト用にクラッシュさせる", systemImage: "ladybug")
        }
      } header: {
        Text("開発用")
      } footer: {
        Text("記録の経路を確かめるために、わざとクラッシュします。アプリを開き直すとここに記録が増えているはずです。開発ビルドにしかありません。")
      }
      #endif
    }
    .navigationTitle("診断")
    .onAppear { reload() }
    .confirmationDialog("記録をすべて削除しますか？",
                        isPresented: $confirmingClear,
                        titleVisibility: .visible) {
      Button("削除", role: .destructive) {
        MTCrashReporter.removeAll()
        reload()
      }
      Button("キャンセル", role: .cancel) {}
    }
  }

  @ViewBuilder
  private func row(_ entry: MTDiagnosticEntry) -> some View {
    let record = entry.record
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: record.kind.symbolName)
        .foregroundColor(.orange)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(record.kind.label) · \(Self.dateFormatter.string(from: record.date))")
          .font(MTFont.ui(15, relativeTo: .body))
        Text(record.summary)
          .font(MTFont.ui(12, relativeTo: .caption))
          .foregroundColor(.secondary)
          .lineLimit(2)
      }
    }
  }

  private func reload() {
    entries = MTCrashReporter.load()
  }
}

/// 1 件の全文。共有シートで JSON ファイルそのものを書き出せる。
struct MTDiagnosticDetailView: View {
  let entry: MTDiagnosticEntry

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "yyyy年M月d日 HH:mm:ss"
    return f
  }()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        header
        Divider()
        Text(entry.record.detail)
          .font(MTFont.mono(11))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding()
    }
    .navigationTitle(entry.record.kind.label)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        ShareLink(item: entry.url) {
          Image(systemName: "square.and.arrow.up")
        }
      }
    }
  }

  @ViewBuilder
  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(entry.record.summary)
        .font(MTFont.ui(15, relativeTo: .body))
      Text("日時: \(Self.dateFormatter.string(from: entry.record.date))")
        .font(MTFont.ui(12, relativeTo: .caption))
        .foregroundColor(.secondary)
      Text("アプリ: \(entry.record.appVersion) ／ OS: \(entry.record.osVersion)")
        .font(MTFont.ui(12, relativeTo: .caption))
        .foregroundColor(.secondary)
    }
  }
}
