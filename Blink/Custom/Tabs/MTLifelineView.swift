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
import SwiftUI

// MARK: - ライフライン（06 §2）

/// タブバー直下の 2pt 横線。セッションの連続性を時系列で表す。線は途切れない。
struct MTLifelineView: View {
  @ObservedObject private var center = MTSessionStateCenter.shared
  @ObservedObject private var themeStore = MTThemeStore.shared

  /// 1 秒ごとに再描画（時間経過で線が流れる）
  @State private var now = Date()
  private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  private var theme: MTTheme { themeStore.currentTheme }

  var body: some View {
    let key = center.currentKey
    let state = key.map { center.state(for: $0) } ?? .connected
    let timeline = key.map { center.timeline(for: $0) }

    VStack(spacing: 3) {
      GeometryReader { geo in
        lifelineCanvas(timeline: timeline, state: state, size: geo.size)
          // スクラブ: なぞった位置の時刻の画面を読み取り専用で出す（07 #01）
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 4)
              .onChanged { value in
                scrub(at: value.location.x, width: geo.size.width, timeline: timeline, key: key)
              }
              .onEnded { _ in
                MTScreenHistory.shared.scrubbing = nil
              }
          )
      }
      .frame(height: 10)

      summaryRow(timeline: timeline, state: state)
    }
    .padding(.horizontal, 8)
    .padding(.bottom, 3)
    .background(theme.bg.color)
    .onReceive(tick) { now = $0 }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("ライフライン。\(state.label)"))
  }

  /// なぞった位置を時刻に直し、その頃の画面を出す
  private func scrub(at x: CGFloat, width: CGFloat, timeline: MTSessionTimeline?, key: UUID?) {
    guard let key, let timeline, width > 0 else { return }
    let window: TimeInterval = min(max(now.timeIntervalSince(timeline.start), 60), 30 * 60)
    let ratio = min(max(x / width, 0), 1)
    let date = now.addingTimeInterval(-window * (1 - Double(ratio)))
    MTScreenHistory.shared.scrubbing = MTScreenHistory.shared.snapshot(for: key, at: date)
  }

  private func color(for state: MTSessionState) -> Color {
    switch state {
    case .connected: return theme.ok.color
    case .reconnecting: return theme.warn.color
    case .held: return theme.bad.color
    case .restored: return theme.restore.color
    }
  }

  private func dash(for state: MTSessionState) -> [CGFloat] {
    switch state {
    case .reconnecting: return [3, 3]  // 点線 3/3
    case .held: return [2, 6]          // 粗い点線 2/6
    default: return []                 // 実線
    }
  }

  @ViewBuilder
  private func lifelineCanvas(timeline: MTSessionTimeline?, state: MTSessionState, size: CGSize) -> some View {
    let dotSize: CGFloat = 10
    let lineWidth = size.width - dotSize
    let y = size.height / 2

    Canvas { context, _ in
      guard let timeline, lineWidth > 0 else {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: lineWidth, y: y))
        context.stroke(path, with: .color(color(for: .connected)), lineWidth: 2)
        return
      }

      // 表示窓: 直近 30 分（セッションがそれより若ければ開始から）
      let window: TimeInterval = min(max(now.timeIntervalSince(timeline.start), 60), 30 * 60)
      let windowStart = now.addingTimeInterval(-window)

      func x(_ date: Date) -> CGFloat {
        let t = date.timeIntervalSince(windowStart) / window
        return CGFloat(min(max(t, 0), 1)) * lineWidth
      }

      var events = timeline.events
      if events.isEmpty { events = [(timeline.start, .connected)] }

      for (idx, event) in events.enumerated() {
        let from = max(event.date, windowStart)
        let to = idx + 1 < events.count ? events[idx + 1].date : now
        guard to > windowStart else { continue }
        var path = Path()
        path.move(to: CGPoint(x: x(from), y: y))
        path.addLine(to: CGPoint(x: x(to), y: y))
        context.stroke(
          path,
          with: .color(color(for: event.state)),
          style: StrokeStyle(lineWidth: 2, dash: dash(for: event.state)))
      }
    }
    .overlay(alignment: .trailing) {
      // 右端に現在位置の丸（10pt）
      Circle()
        .fill(color(for: state))
        .frame(width: dotSize, height: dotSize)
    }
  }

  @ViewBuilder
  private func summaryRow(timeline: MTSessionTimeline?, state: MTSessionState) -> some View {
    HStack {
      Text(summaryText(timeline: timeline, state: state))
        .font(MTFont.mono(11))
        .foregroundColor(state == .connected ? theme.muted.color : color(for: state))
        .lineLimit(1)
      Spacer()
    }
  }

  private func summaryText(timeline: MTSessionTimeline?, state: MTSessionState) -> String {
    switch state {
    case .connected, .restored:
      let duration = timeline.map { now.timeIntervalSince($0.start) } ?? 0
      let switches = timeline?.switchCount ?? 0
      let head = state == .restored ? "復元済み · " : ""
      // 「欠落 0」は計測せずに固定で出していた。実際には NWPathMonitor で経路の
      // 変化を見ているだけで、パケットの取りこぼしは一切数えていないため、
      // 嘘になる（パケットロスや高 RTT でも 0 のまま）。計測できていない値は出さない。
      return "\(head)連続 \(Self.duration(duration)) · 回線切替 \(switches)"
    case .reconnecting:
      return "再接続中 · \(center.networkChange ?? "回線を切り替えています")"
    case .held:
      if let last = timeline?.lastConnectedDate {
        return "保持中 · 最終応答 \(Self.ago(now.timeIntervalSince(last)))"
      }
      return "保持中"
    }
  }

  static func duration(_ interval: TimeInterval) -> String {
    let s = Int(max(interval, 0))
    if s >= 3600 { return "\(s / 3600)h\((s % 3600) / 60)m" }
    if s >= 60 { return "\(s / 60)m" }
    return "\(s)s"
  }

  static func ago(_ interval: TimeInterval) -> String {
    let s = Int(max(interval, 0))
    if s >= 3600 { return "\(s / 3600)時間前" }
    if s >= 60 { return "\(s / 60)分前" }
    return "\(s)秒前"
  }
}

// MARK: - 状態バナー・トースト（06 §4.1「伝え方のはしご」）

/// ターミナルに重ねる表示専用オーバーレイ。
/// 0 秒: バッジ・ライフライン（別ビュー）→ 3 秒: バナー → 復帰時: トースト 2.5 秒。
struct MTStatusOverlayView: View {
  @ObservedObject private var center = MTSessionStateCenter.shared
  @ObservedObject private var themeStore = MTThemeStore.shared

  @State private var bannerVisible = false
  @State private var toast: (title: String, detail: String)? = nil
  @State private var disconnectedSince: Date? = nil
  @State private var lastState: MTSessionState = .connected

  private var theme: MTTheme { themeStore.currentTheme }

  private var currentState: MTSessionState {
    center.currentKey.map { center.state(for: $0) } ?? .connected
  }

  var body: some View {
    let state = currentState

    VStack(spacing: 8) {
      if bannerVisible, state == .reconnecting || state == .held {
        banner(for: state)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
      if let toast {
        toastView(toast)
          .transition(.opacity)
      }
      Spacer(minLength: 0)

      // 入力モードピル（06 §5.2、ターミナル右下）
      HStack {
        Spacer()
        MTInputModePill()
      }
      .padding(.bottom, 8)
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .animation(.easeInOut(duration: 0.25), value: bannerVisible)
    .animation(.easeInOut(duration: 0.25), value: toast?.title)
    .onChange(of: currentState) { old, new in
      handleTransition(from: old, to: new)
    }
    // 3 秒経っても戻らなければバナーを出す
    .task(id: taskToken) {
      guard currentState == .reconnecting || currentState == .held else { return }
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      if currentState == .reconnecting || currentState == .held {
        bannerVisible = true
      }
    }
  }

  private var taskToken: String {
    "\(center.currentKey?.uuidString ?? "-")/\(currentState.label)"
  }

  private func handleTransition(from old: MTSessionState, to new: MTSessionState) {
    switch (old, new) {
    case (.connected, .reconnecting), (.connected, .held), (.restored, .reconnecting), (.restored, .held):
      disconnectedSince = Date()
    case (.reconnecting, .connected), (.held, .connected):
      bannerVisible = false
      let gap = disconnectedSince.map { Date().timeIntervalSince($0) }
      disconnectedSince = nil
      let detail = gap.map { "\(Int($0.rounded())) 秒の断を吸収しました。" } ?? ""
      // 同上。復帰は分かるが、欠落が無かったことは確かめていない。
      showToast(title: "復帰しました", detail: detail)
    default:
      break
    }
    lastState = new
  }

  private func showToast(title: String, detail: String) {
    toast = (title, detail)
    Task {
      try? await Task.sleep(nanoseconds: 2_500_000_000)
      toast = nil
    }
  }

  @ViewBuilder
  private func banner(for state: MTSessionState) -> some View {
    let (title, sub): (String, String) = state == .reconnecting
      ? ("回線を切り替えています",
         "入力は手元に保持中。つながり次第そのまま送ります。")
      : ("回線が切れています（セッションは保持）",
         "サーバー側で作業は続いています。電波が戻れば自動で復帰します。")
    let accent = state == .reconnecting ? theme.warn.color : theme.bad.color

    HStack(alignment: .top, spacing: 10) {
      RoundedRectangle(cornerRadius: 1.5)
        .fill(accent)
        .frame(width: 3)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(MTFont.ui(13, .medium))
          .foregroundColor(theme.text.color)
        Text(sub)
          .font(MTFont.ui(12))
          .foregroundColor(theme.sub.color)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 10).fill(theme.raised.color))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line.color, lineWidth: 1))
  }

  @ViewBuilder
  private func toastView(_ toast: (title: String, detail: String)) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(toast.title)
        .font(MTFont.ui(13, .medium))
        .foregroundColor(theme.text.color)
      if !toast.detail.isEmpty {
        Text(toast.detail)
          .font(MTFont.ui(12))
          .foregroundColor(theme.sub.color)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(RoundedRectangle(cornerRadius: 10).fill(theme.okBg.color))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.ok.color, lineWidth: 1))
  }
}
