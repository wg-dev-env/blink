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
import Network

/// 回線の状態を監視し、セッション状態（06 §4）へ変換する。
/// - 圏外 → 全セッション「保持」
/// - 復帰・回線切替（Wi-Fi ↔ モバイル等）→「再接続中」→ 少し置いて「接続中」
///   （Mosh が吸収する想定の表示。実際の疎通確認との配線は今後の改善）
final class MTConnectivityMonitor {
  static let shared = MTConnectivityMonitor()

  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "mt.connectivity")
  private var started = false
  private var lastInterface: String? = nil
  private var lastSatisfied = true
  private var recoveryWork: DispatchWorkItem? = nil

  private init() {}

  func startIfNeeded() {
    guard !started else { return }
    started = true
    monitor.pathUpdateHandler = { [weak self] path in
      DispatchQueue.main.async { self?.handle(path) }
    }
    monitor.start(queue: queue)
  }

  private func interfaceName(_ path: NWPath) -> String {
    if path.usesInterfaceType(.wifi) { return "Wi-Fi" }
    if path.usesInterfaceType(.cellular) { return "モバイル回線" }
    if path.usesInterfaceType(.wiredEthernet) { return "有線" }
    return "ネットワーク"
  }

  private func handle(_ path: NWPath) {
    let center = MTSessionStateCenter.shared
    let satisfied = path.status == .satisfied
    let iface = satisfied ? interfaceName(path) : nil
    defer {
      lastSatisfied = satisfied
      if let iface { lastInterface = iface }
    }

    if !satisfied {
      guard lastSatisfied else { return }
      recoveryWork?.cancel()
      center.networkChange = nil
      center.transitionAll(to: .held)
      return
    }

    if !lastSatisfied {
      // 圏外からの復帰
      center.networkChange = lastInterface.flatMap { $0 == iface ? iface : "\($0) → \(iface!)" } ?? iface
      center.transitionAll(to: .reconnecting)
      scheduleRecovery()
      return
    }

    if let last = lastInterface, let iface, last != iface {
      // 回線の切り替え（Wi-Fi ↔ モバイル等）
      center.networkChange = "\(last) → \(iface)"
      center.transitionAll(to: .reconnecting)
      scheduleRecovery()
    }
  }

  /// 復帰表示の保険。
  ///
  /// 本来の合図はサーバーからの出力（`MTSessionStateCenter.noteTraffic`。
  /// TermDevice → TermController 経由）で、届けばこれより先に「接続中」へ戻る。
  /// ここは出力が来ないまま待たされ続けないための保険なので、固定時間で
  /// 「復帰した」ことにしてしまわないよう、実疎通より十分あとに置く。
  private func scheduleRecovery() {
    recoveryWork?.cancel()
    let work = DispatchWorkItem { MTSessionStateCenter.shared.recoverAll() }
    recoveryWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.recoveryFallbackDelay, execute: work)
  }

  /// 出力が来ないときに表示を戻すまでの猶予（秒）
  static let recoveryFallbackDelay: TimeInterval = 6
}
