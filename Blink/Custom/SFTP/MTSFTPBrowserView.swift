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
import UniformTypeIdentifiers

/// 容量の表記。一覧と「送りました」のメッセージで同じ見た目にする。
enum MTSFTPFormat {
  static func bytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }
}

/// 送る直前の確認に出す内容（選んだローカルのファイルと、その送信先）
struct MTSFTPPendingUpload: Identifiable {
  var id: String { destination }
  let url: URL
  let name: String
  let destination: String
  /// 送信先に同名のファイルが既にある（上書きになる）
  let overwrite: Bool
}

/// SFTP ファイルブラウザ（S16）。接続先の長押しメニューから開く。
/// 一覧・移動・ダウンロード（書き出し）・アップロード（取り込み）ができる。
@MainActor
final class MTSFTPModel: ObservableObject {
  @Published var entries: [MTSFTPEntry] = []
  @Published var path: String = "."
  @Published var loading = false
  @Published var errorText: String?
  /// 接続失敗がホスト鍵の不一致によるものだったか（「鍵を忘れて再接続」導線の表示判定）
  @Published var hostKeyMismatch = false
  /// 「送りました」などの完了メッセージ（次の操作で消える）
  @Published var noticeText: String?

  let alias: String
  private let session: MTSFTPSession
  private var connected = false

  init(alias: String) {
    self.alias = alias
    self.session = MTSFTPSession(alias: alias)
  }

  func start() async {
    guard !connected else { return }
    loading = true; errorText = nil; hostKeyMismatch = false
    do {
      try await session.connect()
      connected = true
      await reload()
    } catch {
      errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      hostKeyMismatch = MTTofuHostKeyValidator.isHostKeyChanged(error)
    }
    loading = false
  }

  /// 記録済みのホスト鍵指紋を破棄して接続し直す。
  /// サーバー再構築などで鍵が正当に変わったときの復旧手段（次の接続で新しい鍵を再記録する）
  func forgetHostKeyAndRetry() async {
    MTTofuHostKeyValidator.reset(hostID: alias)
    hostKeyMismatch = false
    await start()
  }

  func reload() async {
    // 取得中に別のディレクトリへ移ると、遅れて返ってきた応答が今の一覧を
    // 上書きしてしまう。`path` と `entries` が食い違うと、送信先の表示と
    // 実際の送り先がずれるため、要求時のパスと照合してから反映する
    let requested = path
    loading = true; errorText = nil; noticeText = nil
    do {
      let listed = try await session.list(requested)
      guard requested == path else { return }  // 追い越された。古い応答は捨てる
      entries = listed
    } catch {
      guard requested == path else { return }
      errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
    loading = false
  }

  func enter(_ entry: MTSFTPEntry) {
    guard entry.isDirectory else { return }
    path = (path == "." || path.isEmpty) ? entry.name : "\(path)/\(entry.name)"
    Task { await reload() }
  }

  var canGoUp: Bool { path != "." && !path.isEmpty }

  func goUp() {
    guard canGoUp else { return }
    if let idx = path.lastIndex(of: "/") {
      path = String(path[path.startIndex..<idx])
      if path.isEmpty { path = "." }
    } else {
      path = "."
    }
    Task { await reload() }
  }

  func fullPath(_ entry: MTSFTPEntry) -> String { destination(for: entry.name) }

  /// 今開いているディレクトリに `name` を置いたときのパス（確認ダイアログに出す）
  func destination(for name: String) -> String {
    (path == "." || path.isEmpty) ? name : "\(path)/\(name)"
  }

  /// 今開いているディレクトリの表示名（フッターの案内に出す）
  var pathLabel: String { (path == "." || path.isEmpty) ? "ホーム" : path }

  /// 送信先に同名のファイルがあるか。アップロードは上書きになるので事前に伝える
  func willOverwrite(_ name: String) -> Bool {
    entries.contains { !$0.isDirectory && $0.name == name }
  }

  /// ローカルで選んだファイルから、確認ダイアログに出す内容を作る
  func pendingUpload(for url: URL) -> MTSFTPPendingUpload {
    let name = url.lastPathComponent
    return MTSFTPPendingUpload(url: url, name: name,
                               destination: destination(for: name),
                               overwrite: willOverwrite(name))
  }

  func download(_ entry: MTSFTPEntry) async -> Data? {
    loading = true; errorText = nil
    defer { loading = false }
    do {
      return try await session.download(fullPath(entry))
    } catch {
      errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      return nil
    }
  }

  func upload(from url: URL) async {
    loading = true; errorText = nil; noticeText = nil
    defer { loading = false }
    do {
      let needsStop = url.startAccessingSecurityScopedResource()
      defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
      let data = try Data(contentsOf: url)
      let name = url.lastPathComponent
      try await session.upload(data, to: destination(for: name))
      await reload()
      // reload() が消すので、一覧を取り直した後に出す
      noticeText = "\(name) を送りました（\(MTSFTPFormat.bytes(UInt64(data.count)))）"
    } catch {
      errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
  }

  func close() async { await session.disconnect() }
}

/// ダウンロードしたデータを書き出すための軽量ドキュメント
struct MTSFTPDownload: FileDocument {
  static var readableContentTypes: [UTType] { [.data] }
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

struct MTSFTPBrowserView: View {
  @StateObject private var model: MTSFTPModel
  @Environment(\.dismiss) private var dismiss

  @State private var importing = false
  /// 選び終えてから「送る」を押すまでの間、確認内容を持つ
  @State private var pending: MTSFTPPendingUpload?
  @State private var exporting = false
  @State private var exportDoc: MTSFTPDownload?
  @State private var exportName = "download"

  init(alias: String) {
    _model = StateObject(wrappedValue: MTSFTPModel(alias: alias))
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        List {
          if model.canGoUp {
            Button {
              model.goUp()
            } label: {
              Label("上の階層へ", systemImage: "arrow.up.left")
            }
          }
          ForEach(model.entries) { entry in
            row(entry)
          }
        }
        .overlay {
          if model.loading { ProgressView() }
          else if model.entries.isEmpty, model.errorText == nil {
            ContentUnavailableView("ファイルはありません", systemImage: "folder")
          }
        }
        .navigationTitle(model.path == "." ? model.alias : model.path)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("閉じる") { Task { await model.close(); dismiss() } }
          }
          ToolbarItemGroup(placement: .primaryAction) {
            // ナビゲーションバーは Label の文字を落としてアイコンだけにするため、
            // 「送る」の向きが伝わるよう自前でアイコンと文字を並べる
            Button { importing = true } label: {
              HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                Text("送る")
              }
            }
            Button { Task { await model.reload() } } label: { Image(systemName: "arrow.clockwise") }
          }
        }
        footer
      }
    }
    .task { await model.start() }
    // 「閉じる」ボタンだけでなく、下スワイプで閉じたときも接続を畳む
    // （pageSheet は下スワイプが標準の閉じ方で、以前は繋ぎっぱなしになっていた）
    .onDisappear { Task { await model.close() } }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
      if case .success(let url) = result {
        pending = model.pendingUpload(for: url)
      }
    }
    .alert(pending.map { "\($0.name) を送ります" } ?? "",
           isPresented: Binding(get: { pending != nil },
                                set: { if !$0 { pending = nil } }),
           presenting: pending) { item in
      Button("やめる", role: .cancel) {}
      Button("送る", role: item.overwrite ? .destructive : nil) {
        Task { await model.upload(from: item.url) }
      }
    } message: { item in
      Text(item.overwrite
           ? "送信先：\(model.alias):\(item.destination)\n\n同名のファイルがあります。上書きされます。"
           : "送信先：\(model.alias):\(item.destination)")
    }
    .fileExporter(isPresented: $exporting, document: exportDoc,
                  contentType: .data, defaultFilename: exportName) { _ in }
  }

  /// 画面下の案内。エラー・完了メッセージ・常設の送信先案内を 1 つだけ出す。
  /// 常設案内は「どこへ送るのか」を見せるためのもので、何も起きていないときに表示する
  @ViewBuilder
  private var footer: some View {
    if let err = model.errorText {
      VStack(spacing: 8) {
        Text(err)
          .font(.footnote)
          .foregroundColor(.white)
        if model.hostKeyMismatch {
          // 正当な鍵変更（サーバー再構築など）からの復旧導線。
          // 心当たりがない場合に押してはいけないことを文言で伝える
          Button("サーバーを作り直した場合：以前の鍵を忘れて再接続") {
            Task { await model.forgetHostKeyAndRetry() }
          }
          .font(.footnote.bold())
          .foregroundColor(.white)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity)
      .background(Color.red.opacity(0.9))
    } else if let notice = model.noticeText {
      Label(notice, systemImage: "checkmark.circle.fill")
        .font(.footnote)
        .foregroundColor(.white)
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.9))
    } else {
      Label("この端末から \(model.pathLabel) へ送ります", systemImage: "square.and.arrow.up")
        .font(.footnote)
        .foregroundColor(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
  }

  @ViewBuilder
  private func row(_ entry: MTSFTPEntry) -> some View {
    Button {
      if entry.isDirectory {
        model.enter(entry)
      } else {
        Task {
          if let data = await model.download(entry) {
            exportDoc = MTSFTPDownload(data: data)
            exportName = entry.name
            exporting = true
          }
        }
      }
    } label: {
      HStack {
        Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
          .foregroundColor(entry.isDirectory ? .accentColor : .secondary)
        Text(entry.name).foregroundColor(.primary)
        Spacer()
        if entry.isDirectory {
          Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        } else if let size = entry.size {
          Text(byteString(size)).font(.caption).foregroundColor(.secondary)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func byteString(_ bytes: UInt64) -> String { MTSFTPFormat.bytes(bytes) }
}
