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

import Combine
import Foundation
import UIKit

// MARK: - 画面のスナップショット（07 #01 ライフライン・スクラブ）

struct MTScreenSnapshot: Identifiable, Equatable {
  let id = UUID()
  let date: Date
  let text: String
  let cols: Int
  let rows: Int
  /// vim / tmux などの代替画面だったか
  let alternate: Bool
  /// 撮った理由（回線切替・復元・定期）
  let reason: String

  init?(dictionary: [String: Any], date: Date = Date(), reason: String) {
    guard let text = dictionary["text"] as? String else { return nil }
    self.date = date
    self.text = text
    self.cols = (dictionary["cols"] as? NSNumber)?.intValue ?? 0
    self.rows = (dictionary["rows"] as? NSNumber)?.intValue ?? 0
    self.alternate = (dictionary["alternate"] as? NSNumber)?.boolValue ?? false
    self.reason = reason
  }
}

/// セッションごとの画面履歴。直近 24 時間・最大 N 枚（07 #01 の受け入れ条件）
final class MTScreenHistory: ObservableObject {
  static let shared = MTScreenHistory()

  private static let maxPerSession = 48
  private static let maxAge: TimeInterval = 24 * 60 * 60

  @Published private(set) var snapshots: [UUID: [MTScreenSnapshot]] = [:]
  /// スクラブ中に表示しているスナップショット
  @Published var scrubbing: MTScreenSnapshot? = nil

  private init() {}

  func snapshots(for key: UUID) -> [MTScreenSnapshot] { snapshots[key] ?? [] }

  func add(_ snapshot: MTScreenSnapshot, for key: UUID) {
    // 空の画面は残さない（接続直後など）
    guard !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    var list = snapshots[key] ?? []
    // 直前と中身が同じなら更新だけ
    if let last = list.last, last.text == snapshot.text {
      return
    }
    list.append(snapshot)
    let cutoff = Date().addingTimeInterval(-Self.maxAge)
    list.removeAll { $0.date < cutoff }
    if list.count > Self.maxPerSession {
      list.removeFirst(list.count - Self.maxPerSession)
    }
    snapshots[key] = list
  }

  func clear(for key: UUID) {
    snapshots.removeValue(forKey: key)
  }

  /// 指定時刻に最も近いスナップショット（スクラブ用）
  func snapshot(for key: UUID, at date: Date) -> MTScreenSnapshot? {
    let list = snapshots(for: key)
    guard !list.isEmpty else { return nil }
    return list.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
  }
}

// MARK: - コマンドブロック（07 #05）

struct MTCommandBlock: Identifiable, Equatable {
  let id = UUID()
  let date: Date
  let command: String
  let output: String
  let exitCode: Int
  let duration: TimeInterval

  var succeeded: Bool { exitCode == 0 }

  var durationLabel: String {
    if duration >= 60 { return String(format: "%.0f分%02.0f秒", duration / 60, duration.truncatingRemainder(dividingBy: 60)) }
    if duration >= 1 { return String(format: "%.1f秒", duration) }
    return String(format: "%.0fms", duration * 1000)
  }
}

/// シェル統合（OSC 133）から届いたコマンドブロックの置き場。
/// 統合が入っていない環境では何も届かず、UI も出ない。
final class MTCommandBlockStore: ObservableObject {
  static let shared = MTCommandBlockStore()

  private static let maxPerSession = 50

  @Published private(set) var blocks: [UUID: [MTCommandBlock]] = [:]

  private init() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(handleBlock(_:)),
      name: NSNotification.Name("MTCommandBlockDidFinish"), object: nil)
  }

  func blocks(for key: UUID) -> [MTCommandBlock] { blocks[key] ?? [] }

  func hasBlocks(for key: UUID?) -> Bool {
    guard let key else { return false }
    return !(blocks[key] ?? []).isEmpty
  }

  func clear(for key: UUID) {
    blocks.removeValue(forKey: key)
  }

  @objc private func handleBlock(_ note: Notification) {
    guard let info = note.userInfo,
          let controller = info["controller"] as? TermController else { return }
    let key = controller.meta.key

    let command = (info["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let output = info["output"] as? String ?? ""
    let exitCode = (info["exitCode"] as? NSNumber)?.intValue ?? 0
    let duration = (info["duration"] as? NSNumber)?.doubleValue ?? 0

    // コマンドが取れないものは一覧に出しても意味がない
    guard !command.isEmpty || !output.isEmpty else { return }

    let block = MTCommandBlock(
      date: Date(), command: command, output: output,
      exitCode: exitCode, duration: duration)

    DispatchQueue.main.async {
      var list = self.blocks[key] ?? []
      list.append(block)
      if list.count > Self.maxPerSession {
        list.removeFirst(list.count - Self.maxPerSession)
      }
      self.blocks[key] = list
    }
  }
}
