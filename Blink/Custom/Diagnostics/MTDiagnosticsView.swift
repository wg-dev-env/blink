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

      Section {
        NavigationLink {
          MTKeyProbeView()
        } label: {
          Label("キー入力の確認", systemImage: "keyboard")
        }
      } footer: {
        Text("外付けキーボードの打鍵がアプリまで届いているかを見ます。切り替えキーが効かないときの切り分けに使います。")
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

// MARK: - キー入力の確認（S25）

/// 外付けキーボードの打鍵がアプリまで届いているかを記録する。
/// iPadOS が先に取るキー（入力ソース切替など）はここに現れない ＝ それが答えになる。
/// 既定は OFF。診断画面で ON にしてから端末で打ち、戻って記録を見る。
/// 記録は端末のメモリ上にだけ置き、どこへも送信しない。
final class MTKeyProbe: ObservableObject {
  static let shared = MTKeyProbe()
  static let enabledDefaultsKey = "MTKeyProbeEnabled"

  struct Record: Identifiable {
    let id = UUID()
    let at: Date
    let keyName: String
    let keyCode: Int
    let modifiers: String
    let characters: String
    let note: String
  }

  @Published private(set) var records: [Record] = []

  private init() {}

  private static let limit = 40

  var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey) }

  /// KBWebView.pressesBegan から（メインスレッド）
  func note(_ key: UIKey, note: String) {
    guard enabled else { return }
    let record = Record(at: Date(),
                        keyName: Self.keyName(key.keyCode),
                        keyCode: key.keyCode.rawValue,
                        modifiers: Self.modifierText(key.modifierFlags),
                        characters: Self.printable(key.characters),
                        note: note)
    records.insert(record, at: 0)
    if records.count > Self.limit { records.removeLast(records.count - Self.limit) }
  }

  func removeAll() { records.removeAll() }

  private static func keyName(_ code: UIKeyboardHIDUsage) -> String {
    switch code {
    case .keyboardSpacebar: return "Space"
    case .keyboardLANG1: return "かな（LANG1）"
    case .keyboardLANG2: return "英数（LANG2）"
    case .keyboardInternational2: return "変換（Intl2）"
    case .keyboardInternational5: return "無変換（Intl5）"
    case .keyboardReturnOrEnter: return "Enter"
    case .keyboardTab: return "Tab"
    case .keyboardEscape: return "Esc"
    case .keyboardDeleteOrBackspace: return "Backspace"
    case .keyboardCapsLock: return "Caps Lock"
    default: return "キー"
    }
  }

  private static func modifierText(_ flags: UIKeyModifierFlags) -> String {
    var parts: [String] = []
    if flags.contains(.control) { parts.append("Ctrl") }
    if flags.contains(.shift) { parts.append("Shift") }
    if flags.contains(.alternate) { parts.append("Option") }
    if flags.contains(.command) { parts.append("Cmd") }
    if flags.contains(.alphaShift) { parts.append("CapsLock") }
    return parts.isEmpty ? "なし" : parts.joined(separator: "+")
  }

  /// 制御文字は U+XXXX で見せる（NUL などを目で確かめられるように）
  private static func printable(_ text: String) -> String {
    guard !text.isEmpty else { return "（なし）" }
    return text.unicodeScalars.map { scalar in
      (scalar.value < 0x20 || scalar.value == 0x7F)
        ? String(format: "U+%04X", scalar.value)
        : String(scalar)
    }.joined()
  }
}

/// 設定 › 診断 › キー入力の確認。
/// 「キーがアプリまで届いているか」を見るための画面。届いていないキーは
/// iPadOS が先に取っている（入力ソース切替など）ということ。
struct MTKeyProbeView: View {
  @ObservedObject private var probe = MTKeyProbe.shared
  @AppStorage(MTKeyProbe.enabledDefaultsKey) private var enabled = false

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "HH:mm:ss.SSS"
    return f
  }()

  var body: some View {
    List {
      Section {
        Toggle("キー入力を記録する", isOn: $enabled)
      } footer: {
        Text("ON にしてからこの画面を閉じ、ターミナルで確かめたいキーを押して、ここへ戻ってください。記録はアプリを終了すると消え、どこへも送信しません。\n\n押したのに記録に出ないキーは、iPadOS が先に取っています（入力ソースの切り替えなど）。その場合はアプリ側では受け取れません。")
      }

      Section {
        if probe.records.isEmpty {
          Text(enabled ? "記録はまだありません。" : "記録は止まっています。")
            .foregroundColor(.secondary)
        } else {
          ForEach(probe.records) { record in
            VStack(alignment: .leading, spacing: 2) {
              Text("\(record.modifiers) + \(record.keyName)")
                .font(MTFont.ui(15, relativeTo: .body))
              Text("keyCode \(record.keyCode) ／ 文字 \(record.characters)")
                .font(MTFont.ui(12, relativeTo: .caption))
                .foregroundColor(.secondary)
              if !record.note.isEmpty {
                Text(record.note)
                  .font(MTFont.ui(12, relativeTo: .caption))
                  .foregroundColor(.secondary)
              }
              Text(Self.timeFormatter.string(from: record.at))
                .font(MTFont.ui(11, relativeTo: .caption2))
                .foregroundColor(.secondary)
            }
          }
        }
      } header: {
        Text("最近の打鍵（新しい順・最大 40 件）")
      }

      if !probe.records.isEmpty {
        Section {
          Button(role: .destructive) { probe.removeAll() } label: { Text("記録を消す") }
        }
      }
    }
    .navigationTitle("キー入力の確認")
  }
}
