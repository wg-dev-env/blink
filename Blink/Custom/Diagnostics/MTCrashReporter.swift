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

import Foundation
import MetricKit
import UIKit

/// 診断記録 1 件（クラッシュ・ハング・未捕捉例外）。
public struct MTDiagnosticRecord: Codable {
  public enum Kind: String, Codable {
    /// MetricKit が次回起動時に渡してくるクラッシュ診断
    case crash
    /// MetricKit のハング診断（メインスレッドが応答しなかった）
    case hang
    /// NSSetUncaughtExceptionHandler で落ちる直前に自分で書いた Obj-C 例外
    case exception

    public var label: String {
      switch self {
      case .crash: return "クラッシュ"
      case .hang: return "ハング（無応答）"
      case .exception: return "例外"
      }
    }

    public var symbolName: String {
      switch self {
      case .crash: return "exclamationmark.triangle.fill"
      case .hang: return "hourglass"
      case .exception: return "xmark.octagon.fill"
      }
    }
  }

  public let id: String
  public let date: Date
  public let kind: Kind
  /// 一覧に出す 1 行要約（例外名・終了理由など）
  public let summary: String
  public let appVersion: String
  public let osVersion: String
  /// 全文。クラッシュ／ハングは MetricKit の JSON、例外は名前・理由・コールスタック。
  /// コールスタックは未シンボル化なので `tools/symbolicate_crash.py` で解決する。
  public let detail: String
}

/// ディスク上の 1 件（共有シート用に実ファイルの URL も持つ）
public struct MTDiagnosticEntry: Identifiable {
  public let url: URL
  public let record: MTDiagnosticRecord
  public var id: String { record.id }
}

/// 直前に入っていた未捕捉例外ハンドラ。必ず呼び戻すためにここへ退避する。
/// （C 関数ポインタからは変数キャプチャができないのでファイルスコープに置く）
private var _mtPreviousExceptionHandler: (@convention(c) (NSException) -> Void)?

/// クラッシュ・ハングの記録係。
///
/// 本アプリにはこれまでクラッシュ収集の仕組みが無く、「たまに落ちる」の切り分けが
/// できなかった。追加 SDK を入れず（GPL-3.0 方針と衝突しない）、
///
///  - MetricKit（`MXCrashDiagnostic` / `MXHangDiagnostic`）… OS が集めた診断を次回起動時に受け取る
///  - `NSSetUncaughtExceptionHandler` … Obj-C 例外を落ちる直前に自分で書き出す
///
/// の 2 本立てで記録する。MetricKit は一部の iOS で診断が返らない報告があるため、
/// 例外ハンドラと併用するのが定石。
///
/// 記録はアプリ内（Application Support/diagnostics）に JSON で置き、
/// 設定 › 診断 から読んで共有シートで書き出せる。外部へは一切送信しない。
@objc public final class MTCrashReporter: NSObject {
  @objc public static let shared = MTCrashReporter()

  /// 保持する件数の上限（古いものから捨てる）
  private static let maxRecords = 20

  private override init() { super.init() }

  /// 起動時に一度だけ呼ぶ（AppDelegate から）。
  @objc public func start() {
    MXMetricManager.shared.add(self)
    Self.installExceptionHandler()
  }

  // MARK: - 保存先

  /// 記録の置き場。`SessionRegistry` のセッション保存先と同じ Application Support 配下。
  static func folder() throws -> URL {
    let fm = FileManager.default
    var url = try fm.url(for: .applicationSupportDirectory,
                         in: .userDomainMask,
                         appropriateFor: nil,
                         create: true)
    url.appendPathComponent("diagnostics")
    var isDir: ObjCBool = false
    if !fm.fileExists(atPath: url.path, isDirectory: &isDir) {
      try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }
    return url
  }

  // MARK: - 読み出し

  /// 新しい順に読み出す。壊れたファイルは黙って飛ばす（診断が原因で落ちては本末転倒）。
  public static func load() -> [MTDiagnosticEntry] {
    guard let dir = try? folder(),
          let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else {
      return []
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let entries: [MTDiagnosticEntry] = urls
      .filter { $0.pathExtension == "json" }
      .compactMap { url in
        guard let data = try? Data(contentsOf: url),
              let record = try? decoder.decode(MTDiagnosticRecord.self, from: data) else {
          return nil
        }
        return MTDiagnosticEntry(url: url, record: record)
      }
    return entries.sorted { $0.record.date > $1.record.date }
  }

  /// 全件削除（設定画面から）
  public static func removeAll() {
    guard let dir = try? folder(),
          let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else {
      return
    }
    for url in urls where url.pathExtension == "json" {
      try? FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - 書き込み

  private static func save(_ record: MTDiagnosticRecord) {
    guard let dir = try? folder() else { return }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(record) else { return }
    let url = dir.appendingPathComponent("\(record.id).json")
    try? data.write(to: url, options: .atomic)
    rotate(in: dir)
  }

  /// 上限を超えた分を古い順に捨てる
  private static func rotate(in dir: URL) {
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
      return
    }
    let jsons = urls.filter { $0.pathExtension == "json" }
    guard jsons.count > maxRecords else { return }
    let sorted = jsons.sorted {
      let l = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      let r = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      return l < r
    }
    for url in sorted.prefix(jsons.count - maxRecords) {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private static func makeID(_ date: Date, _ kind: MTDiagnosticRecord.Kind) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd-HHmmss-SSS"
    return "\(f.string(from: date))-\(kind.rawValue)"
  }

  private static var appVersionString: String {
    let info = Bundle.main.infoDictionary
    let v = info?["CFBundleShortVersionString"] as? String ?? "?"
    let b = info?["CFBundleVersion"] as? String ?? "?"
    return "\(v) (\(b))"
  }

  // MARK: - 未捕捉例外

  private static func installExceptionHandler() {
    _mtPreviousExceptionHandler = NSGetUncaughtExceptionHandler()
    NSSetUncaughtExceptionHandler { exception in
      // プロセスが死ぬ直前なので、キューに逃がさずその場で書き切る
      MTCrashReporter.writeExceptionSynchronously(exception)
      // 元のハンドラがいれば必ず呼び戻す（上流・OS 側の処理を奪わない）
      _mtPreviousExceptionHandler?(exception)
    }
  }

  /// 例外ハンドラから呼ばれる。UIKit に触れない・確保を増やさないことを優先する。
  static func writeExceptionSynchronously(_ exception: NSException) {
    let date = Date()
    let name = exception.name.rawValue
    let reason = exception.reason ?? "(reason なし)"
    var detail = """
    name: \(name)
    reason: \(reason)
    userInfo: \(exception.userInfo.map { String(describing: $0) } ?? "nil")

    callStackSymbols:
    """
    for line in exception.callStackSymbols {
      detail += "\n\(line)"
    }
    detail += "\n\nthread callStackSymbols:"
    for line in Thread.callStackSymbols {
      detail += "\n\(line)"
    }

    let record = MTDiagnosticRecord(
      id: makeID(date, .exception),
      date: date,
      kind: .exception,
      summary: "\(name): \(reason)",
      appVersion: appVersionString,
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      detail: detail
    )
    save(record)
  }

  // MARK: - デバッグ用

  #if BLINK_PUBLISHING_OPTION_DEVELOPER
  /// 記録の経路を実機・シミュレータで確かめるための、意図的なクラッシュ。
  /// 開発ビルドにしか入らない（設定 › 診断 から呼ぶ）。
  /// ※このプロジェクトは developer_setup.xcconfig が SWIFT_ACTIVE_COMPILATION_CONDITIONS を
  ///   丸ごと上書きするため `DEBUG` は定義されない。開発ビルドの判定は
  ///   BLINK_PUBLISHING_OPTION_DEVELOPER を使う（CLAUDE.md / FeatureFlags.swift の規約）。
  @objc public static func debugRaiseTestException() -> Never {
    NSException(
      name: NSExceptionName("MTDiagnosticsSelfTest"),
      reason: "設定 › 診断 からの動作確認用。クラッシュ記録が残れば成功。",
      userInfo: nil
    ).raise()
    // raise() は戻らないが、コンパイラのために
    fatalError("unreachable")
  }
  #endif
}

// MARK: - MetricKit

extension MTCrashReporter: MXMetricManagerSubscriber {
  /// 性能メトリクスは使わない（収集も送信もしない）
  public func didReceive(_ payloads: [MXMetricPayload]) {}

  public func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
      for diagnostic in payload.crashDiagnostics ?? [] {
        Self.save(Self.record(from: diagnostic))
      }
      for diagnostic in payload.hangDiagnostics ?? [] {
        Self.save(Self.record(from: diagnostic))
      }
    }
  }

  private static func prettyJSON(_ data: Data) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: pretty, encoding: .utf8) else {
      return String(data: data, encoding: .utf8) ?? "(読めませんでした)"
    }
    return text
  }

  private static func record(from diagnostic: MXCrashDiagnostic) -> MTDiagnosticRecord {
    let date = Date()
    var parts: [String] = []
    if let type = diagnostic.exceptionType { parts.append("exceptionType \(type)") }
    if let code = diagnostic.exceptionCode { parts.append("code \(code)") }
    if let signal = diagnostic.signal { parts.append("signal \(signal)") }
    if let reason = diagnostic.terminationReason { parts.append(reason) }
    let summary = parts.isEmpty ? "クラッシュ（詳細なし）" : parts.joined(separator: " · ")

    return MTDiagnosticRecord(
      id: makeID(date, .crash),
      date: date,
      kind: .crash,
      summary: summary,
      appVersion: "\(diagnostic.metaData.applicationBuildVersion)",
      osVersion: diagnostic.metaData.osVersion,
      // コールスタックは未シンボル化。offsetIntoBinaryTextSegment を
      // tools/symbolicate_crash.py で dSYM に突き合わせて解決する。
      detail: prettyJSON(diagnostic.jsonRepresentation())
    )
  }

  private static func record(from diagnostic: MXHangDiagnostic) -> MTDiagnosticRecord {
    let date = Date()
    let seconds = diagnostic.hangDuration.converted(to: .seconds).value
    return MTDiagnosticRecord(
      id: makeID(date, .hang),
      date: date,
      kind: .hang,
      summary: String(format: "メインスレッドが %.1f 秒応答しませんでした", seconds),
      appVersion: "\(diagnostic.metaData.applicationBuildVersion)",
      osVersion: diagnostic.metaData.osVersion,
      detail: prettyJSON(diagnostic.jsonRepresentation())
    )
  }
}
