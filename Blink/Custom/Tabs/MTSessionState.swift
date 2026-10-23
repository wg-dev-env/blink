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

/// セッションの接続状態（06 §4）。色＋形の二重表現で表示する。
enum MTSessionState {
  case connected     // 接続中（ok・塗り丸）
  case reconnecting  // 再接続中（warn・輪）
  case held          // 保持＝回線断（bad・横棒）
  case restored      // 復元済み（accent・角丸四角）

  /// VoiceOver 用の読み上げ
  var label: String {
    switch self {
    case .connected: return "接続中"
    case .reconnecting: return "再接続中"
    case .held: return "保持中"
    case .restored: return "復元済み"
    }
  }
}

/// セッション 1 本の状態履歴。ライフライン（06 §2）の描画元。
final class MTSessionTimeline {
  let start: Date
  private(set) var events: [(date: Date, state: MTSessionState)]

  init(start: Date = Date()) {
    self.start = start
    self.events = [(start, .connected)]
  }

  func append(_ state: MTSessionState, at date: Date = Date()) {
    guard events.last?.state != state else { return }
    events.append((date, state))
    if events.count > 200 {
      events.removeFirst(events.count - 200)
    }
  }

  /// 回線切替の回数（再接続中に入った回数）
  var switchCount: Int {
    events.filter { $0.state == .reconnecting }.count
  }

  /// 最後に「接続中」だった時刻（保持中の「最終応答」表示に使う）
  var lastConnectedDate: Date? {
    events.last { $0.state == .connected }?.date
  }
}

/// セッション状態の置き場（セッションキー → 状態・履歴）。
/// 回線イベントは MTConnectivityMonitor が、復元イベントは TermController が流し込む。
final class MTSessionStateCenter: ObservableObject {
  static let shared = MTSessionStateCenter()

  @Published private(set) var states: [UUID: MTSessionState] = [:]
  /// 表示中セッション（SpaceController が更新。ライフライン・バナーの対象）
  @Published var currentKey: UUID? = nil
  /// 直近の回線切替の説明（例 "モバイル回線 → Wi-Fi"）
  @Published var networkChange: String? = nil

  private(set) var timelines: [UUID: MTSessionTimeline] = [:]

  private init() {}

  func state(for key: UUID) -> MTSessionState {
    states[key] ?? .connected
  }

  func timeline(for key: UUID) -> MTSessionTimeline {
    if let t = timelines[key] { return t }
    let t = MTSessionTimeline()
    timelines[key] = t
    return t
  }

  /// セッションを追跡対象に登録する（既知なら何もしない）
  func track(_ key: UUID) {
    guard states[key] == nil else { return }
    states[key] = .connected
    _ = timeline(for: key)
  }

  func set(_ state: MTSessionState, for key: UUID) {
    timeline(for: key).append(state)
    states[key] = state
    if state == .restored {
      scheduleRestoredDecay(for: key)
    }
  }

  func clear(for key: UUID) {
    states.removeValue(forKey: key)
    timelines.removeValue(forKey: key)
  }

  /// 回線イベントは全セッション共通で適用する
  func transitionAll(to state: MTSessionState) {
    for key in states.keys {
      timeline(for: key).append(state)
      states[key] = state
    }
  }

  /// サーバーからの出力が届いたことを知らせる（実疎通の合図）。
  ///
  /// 回線の復帰判定はこれまで NWPathMonitor の経路変化から 2.5 秒後に無条件で
  /// 「接続中」へ戻していたため、遅い回線では実際の再同期より早く表示だけが
  /// 戻っていた。サーバーの出力が 1 バイトでも届けば疎通は確かなので、
  /// そのときは待たずに戻す（2.5 秒の既定は、出力が来ない場合の保険として残す）。
  ///
  /// 端末の出力経路から高頻度で呼ばれるため、状態が変わるときだけ仕事をする。
  func noteTraffic(for key: UUID) {
    guard let state = states[key], state == .reconnecting || state == .held else { return }
    timeline(for: key).append(.connected)
    states[key] = .connected
  }

  /// 再接続中のセッションをまとめて接続中へ戻す（復帰）
  func recoverAll() {
    for (key, state) in states where state == .reconnecting || state == .held {
      timeline(for: key).append(.connected)
      states[key] = .connected
    }
  }

  /// 復元済み表示は一定時間で接続中へ落とす
  private func scheduleRestoredDecay(for key: UUID) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
      guard let self, self.states[key] == .restored else { return }
      self.set(.connected, for: key)
    }
  }
}

/// Obj-C（LayoutConstraintManager.m）から参照するレイアウト定数。
/// タブバー設置時に SpaceController が設定し、端末ビューの上インセットに加算される。
@objc class MTChrome: NSObject {
  @objc static var tabBarTopInset: CGFloat = 0
  /// iPad / Mac のサイドバー（06 §7）表示中の左インセット
  @objc static var sidebarLeftInset: CGFloat = 0
}
