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

import BlinkConfig
import Combine
import Foundation

// MARK: - 入力行の蓄積

/// 1 セッション分の入力行。リモートの readline が持つ行はアプリからは読めないため、
/// 打鍵を自前で積んで近似する（07 #04）。履歴呼び出し・補完が入ると中身は分からなく
/// なるので、その場合は `isOpaque` を立てて「内容不明」として扱う。
final class MTCommandBuffer {
  private(set) var line = ""
  /// 履歴（↑↓）や補完（Tab）が使われ、画面の行とアプリの認識が食い違っている
  private(set) var isOpaque = false

  func reset() {
    line = ""
    isOpaque = false
  }

  /// キー入力を 1 つ取り込む。戻り値は Return が押されたか
  @discardableResult
  func feed(_ data: String) -> Bool {
    switch data {
    case "\r", "\n":
      return true
    case "\u{7f}", "\u{8}":  // Backspace
      if !line.isEmpty { line.removeLast() } else { isOpaque = true }
      return false
    case "\u{3}", "\u{15}", "\u{1b}":  // ^C, ^U, Esc
      reset()
      return false
    default:
      // 矢印・Tab・その他の制御シーケンスは行の中身を変えうるが追跡できない
      if data.hasPrefix("\u{1b}") || data == "\t" {
        isOpaque = true
        return false
      }
      if data.unicodeScalars.allSatisfy({ $0.value >= 32 }) {
        line += data
      } else {
        isOpaque = true
      }
      return false
    }
  }
}

// MARK: - 圏外ドラフト（07 #02）

/// 回線断（保持）中に打たれた行をセッションごとに溜める
final class MTDraftStore: ObservableObject {
  static let shared = MTDraftStore()

  struct Draft: Identifiable, Equatable {
    let id = UUID()
    var text: String
  }

  /// 確定済みの行（Return が押された分）
  @Published private(set) var drafts: [UUID: [Draft]] = [:]
  /// 入力途中の行
  @Published private(set) var partial: [UUID: String] = [:]
  /// 復帰後、送信確認を出しているセッション
  @Published var confirming: UUID? = nil

  private init() {}

  func count(for key: UUID) -> Int { drafts[key]?.count ?? 0 }

  func lines(for key: UUID) -> [Draft] { drafts[key] ?? [] }

  func partialLine(for key: UUID) -> String { partial[key] ?? "" }

  /// 圏外中の打鍵を取り込む。Return で 1 行確定する
  func feed(_ data: String, for key: UUID) {
    switch data {
    case "\r", "\n":
      let text = (partial[key] ?? "").trimmingCharacters(in: .whitespaces)
      partial[key] = ""
      guard !text.isEmpty else { return }
      drafts[key, default: []].append(Draft(text: text))
    case "\u{7f}", "\u{8}":
      if var p = partial[key], !p.isEmpty {
        p.removeLast()
        partial[key] = p
      }
    case "\u{3}", "\u{15}":
      partial[key] = ""
    default:
      guard data.unicodeScalars.allSatisfy({ $0.value >= 32 }) else { return }
      partial[key, default: ""] += data
    }
  }

  func remove(_ draft: Draft, for key: UUID) {
    drafts[key]?.removeAll { $0.id == draft.id }
    if drafts[key]?.isEmpty == true { drafts.removeValue(forKey: key) }
  }

  func discardAll(for key: UUID) {
    drafts.removeValue(forKey: key)
    partial.removeValue(forKey: key)
    if confirming == key { confirming = nil }
  }

  /// 送信して空にする。送信は呼び出し側（端末へ書き込む側）が行う
  func takeAll(for key: UUID) -> [String] {
    let lines = (drafts[key] ?? []).map(\.text)
    discardAll(for: key)
    return lines
  }
}

// MARK: - 設定

/// 安全機能の設定（07 #02/#04）
final class MTSafetySettings: ObservableObject {
  static let shared = MTSafetySettings()

  private static let allHostsGuardKey = "MTDangerGuardAllHosts"
  private static let autoSendDraftsKey = "MTDraftsAutoSend"

  /// 危険コマンドの長押しを全ホストで要求する（既定は本番ホストのみ）
  @Published var guardAllHosts: Bool {
    didSet { UserDefaults.standard.set(guardAllHosts, forKey: Self.allHostsGuardKey) }
  }

  /// 復帰時にドラフトを確認なしで送る（既定は確認してから送る。本番ホストは常に確認）
  @Published var autoSendDrafts: Bool {
    didSet { UserDefaults.standard.set(autoSendDrafts, forKey: Self.autoSendDraftsKey) }
  }

  private init() {
    guardAllHosts = UserDefaults.standard.bool(forKey: Self.allHostsGuardKey)
    autoSendDrafts = UserDefaults.standard.bool(forKey: Self.autoSendDraftsKey)
  }
}

// MARK: - 長押し確定（07 #04）

/// Return を飲み込んで長押しリングを出すための置き場
final class MTDangerGuard: ObservableObject {
  static let shared = MTDangerGuard()

  struct Pending {
    let line: String
    let isOpaque: Bool  // 内容不明（履歴・補完）
    let alias: String?
    let send: () -> Void
  }

  @Published var pending: Pending? = nil

  private init() {}

  func request(_ pending: Pending) {
    self.pending = pending
  }

  func confirm() {
    let p = pending
    pending = nil
    p?.send()
  }

  func cancel() {
    pending = nil
  }
}

// MARK: - 入力の関門

/// SmarterTermInput.onOut から呼ばれ、打鍵をそのまま送るか・ドラフトに回すか・
/// 長押し確定を挟むかを決める。
enum MTInputGuard {

  enum Decision {
    case send          // そのまま端末へ
    case swallow       // 飲み込む（ドラフト化・長押し待ち）
  }

  private static var buffers: [UUID: MTCommandBuffer] = [:]

  static func buffer(for key: UUID) -> MTCommandBuffer {
    if let b = buffers[key] { return b }
    let b = MTCommandBuffer()
    buffers[key] = b
    return b
  }

  static func clear(for key: UUID) {
    buffers.removeValue(forKey: key)
    MTDraftStore.shared.discardAll(for: key)
  }

  /// - Parameters:
  ///   - data: キー入力（1 打鍵ぶん）
  ///   - send: 端末へ書き込むクロージャ（長押し確定後に使う）
  static func handle(_ data: String, send: @escaping (String) -> Void) -> Decision {
    guard let key = MTSessionStateCenter.shared.currentKey else { return .send }

    let env = MTHostContext.shared.environment(for: key)
    let state = MTSessionStateCenter.shared.state(for: key)
    let isRemote = MTHostContext.shared.alias(for: key) != nil

    // 1. 圏外（保持中）はドラフトへ。リモート接続しているセッションだけが対象
    if isRemote, state == .held {
      MTDraftStore.shared.feed(data, for: key)
      return .swallow
    }

    // 2. 通常は打鍵を蓄積し、Return の直前に危険判定
    let buffer = buffer(for: key)
    let isReturn = buffer.feed(data)
    guard isReturn else { return .send }

    let guardActive = env.requiresDangerGuard || MTSafetySettings.shared.guardAllHosts
    guard guardActive, isRemote else {
      buffer.reset()
      return .send
    }

    let dangerous = MTDangerPatterns.isDangerous(buffer.line)
    // 本番では「内容不明」の行も確認を求める（07 #04 の決定）
    let opaqueNeedsGuard = buffer.isOpaque && env == .production
    guard dangerous || opaqueNeedsGuard else {
      buffer.reset()
      return .send
    }

    let line = buffer.line
    let isOpaque = buffer.isOpaque && !dangerous
    let alias = MTHostContext.shared.alias(for: key)
    buffer.reset()

    MTDangerGuard.shared.request(.init(
      line: line,
      isOpaque: isOpaque,
      alias: alias,
      send: { send(data) }
    ))
    return .swallow
  }
}
