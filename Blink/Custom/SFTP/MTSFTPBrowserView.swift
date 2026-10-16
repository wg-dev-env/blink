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

/// SFTP ファイルブラウザ（S16）。接続先の長押しメニューから開く。
/// 一覧・移動・ダウンロード（書き出し）・アップロード（取り込み）ができる。
@MainActor
final class MTSFTPModel: ObservableObject {
  @Published var entries: [MTSFTPEntry] = []
  @Published var path: String = "."
  @Published var loading = false
  @Published var errorText: String?

  let alias: String
  private let session: MTSFTPSession
  private var connected = false

  init(alias: String) {
    self.alias = alias
    self.session = MTSFTPSession(alias: alias)
  }

  func start() async {
    guard !connected else { return }
    loading = true; errorText = nil
    do {
      try await session.connect()
      connected = true
      await reload()
    } catch {
      errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
    loading = false
  }

  func reload() async {
    loading = true; errorText = nil
    do {
      entries = try await session.list(path)
    } catch {
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

  func fullPath(_ entry: MTSFTPEntry) -> String {
    (path == "." || path.isEmpty) ? entry.name : "\(path)/\(entry.name)"
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
    loading = true; errorText = nil
    defer { loading = false }
    do {
      let needsStop = url.startAccessingSecurityScopedResource()
      defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
      let data = try Data(contentsOf: url)
      let name = url.lastPathComponent
      let dest = (path == "." || path.isEmpty) ? name : "\(path)/\(name)"
      try await session.upload(data, to: dest)
      await reload()
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
  @State private var exporting = false
  @State private var exportDoc: MTSFTPDownload?
  @State private var exportName = "download"

  init(alias: String) {
    _model = StateObject(wrappedValue: MTSFTPModel(alias: alias))
  }

  var body: some View {
    NavigationStack {
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
          ContentUnavailableView("からっぽです", systemImage: "folder")
        }
      }
      .navigationTitle(model.path == "." ? model.alias : model.path)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { Task { await model.close(); dismiss() } }
        }
        ToolbarItemGroup(placement: .primaryAction) {
          Button { importing = true } label: { Image(systemName: "square.and.arrow.up") }
          Button { Task { await model.reload() } } label: { Image(systemName: "arrow.clockwise") }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if let err = model.errorText {
          Text(err)
            .font(.footnote)
            .foregroundColor(.white)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.9))
        }
      }
    }
    .task { await model.start() }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
      if case .success(let url) = result {
        Task { await model.upload(from: url) }
      }
    }
    .fileExporter(isPresented: $exporting, document: exportDoc,
                  contentType: .data, defaultFilename: exportName) { _ in }
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

  private func byteString(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }
}
