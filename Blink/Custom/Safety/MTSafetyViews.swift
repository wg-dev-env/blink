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
import SwiftUI

// MARK: - 危険コマンドの長押し確定（07 #04）

/// Return を飲み込んだときに出すリング。1 秒押し続けると送信する。
struct MTDangerRingView: View {
  @ObservedObject private var guardCenter = MTDangerGuard.shared
  @ObservedObject private var themeStore = MTThemeStore.shared

  @State private var progress: CGFloat = 0
  @State private var timer: Timer? = nil

  private let duration: TimeInterval = 1.0
  private var theme: MTTheme { themeStore.currentTheme }

  var body: some View {
    if let pending = guardCenter.pending {
      ZStack {
        theme.bg.color.opacity(0.72)
          .ignoresSafeArea()
          .onTapGesture { cancel() }

        VStack(spacing: 18) {
          VStack(spacing: 6) {
            Text(pending.isOpaque ? "内容を確認できません" : "危険なコマンドです")
              .font(MTFont.ui(16, .bold))
              .foregroundColor(theme.text.color)
            if let alias = pending.alias {
              Text("本番 · \(alias)")
                .font(MTFont.mono(12))
                .foregroundColor(theme.bad.color)
            }
            Text(pending.isOpaque
                 ? "履歴や補完で入った行は中身を読めません。長押しで送信します。"
                 : "長押しで送信します。離すと送りません。")
              .font(MTFont.ui(12))
              .foregroundColor(theme.sub.color)
              .multilineTextAlignment(.center)
          }
          .padding(.horizontal, 24)

          if !pending.line.isEmpty {
            Text(pending.line)
              .font(MTFont.mono(13))
              .foregroundColor(theme.term.color)
              .lineLimit(3)
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .frame(maxWidth: 320)
              .background(RoundedRectangle(cornerRadius: 8).fill(theme.surface.color))
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.bad.color.opacity(0.6), lineWidth: 1))
          }

          // 長押しリング（72pt、bad 色）
          ZStack {
            Circle()
              .stroke(theme.line.color, lineWidth: 5)
            Circle()
              .trim(from: 0, to: progress)
              .stroke(theme.bad.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Image(systemName: "return")
              .font(.system(size: 22, weight: .semibold))
              .foregroundColor(theme.bad.color)
          }
          .frame(width: 72, height: 72)
          .contentShape(Circle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { _ in start() }
              .onEnded { _ in stop() }
          )
          .accessibilityLabel(Text("長押しで送信"))
          .accessibilityHint(Text(pending.line))

          Button("送らない") { cancel() }
            .font(MTFont.ui(14, .medium))
            .foregroundColor(theme.sub.color)
        }
        .padding(24)
      }
      .transition(.opacity)
      .onDisappear { stop() }
    }
  }

  private func start() {
    guard timer == nil else { return }
    let step = 0.02
    timer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { t in
      progress += CGFloat(step / duration)
      if progress >= 1 {
        t.invalidate()
        timer = nil
        progress = 0
        MTDangerGuard.shared.confirm()
      }
    }
  }

  private func stop() {
    timer?.invalidate()
    timer = nil
    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
  }

  private func cancel() {
    stop()
    MTDangerGuard.shared.cancel()
  }
}

// MARK: - 圏外ドラフト（07 #02）

/// 圏外中に溜まった行のカード。復帰時に送るか捨てるかを選ぶ。
struct MTDraftCardView: View {
  let sessionKey: UUID
  let onSend: ([String]) -> Void

  @ObservedObject private var store = MTDraftStore.shared
  @ObservedObject private var themeStore = MTThemeStore.shared

  private var theme: MTTheme { themeStore.currentTheme }

  var body: some View {
    let lines = store.lines(for: sessionKey)
    if !lines.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          Image(systemName: "antenna.radiowaves.left.and.right.slash")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(theme.bad.color)
          Text("圏外 · 送信待ち \(lines.count)")
            .font(MTFont.ui(13, .medium))
            .foregroundColor(theme.text.color)
          Spacer()
        }

        VStack(alignment: .leading, spacing: 4) {
          ForEach(lines) { draft in
            HStack(spacing: 8) {
              Text(draft.text)
                .font(MTFont.mono(12))
                .foregroundColor(theme.term.color)
                .lineLimit(1)
              Spacer()
              Button {
                store.remove(draft, for: sessionKey)
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.system(size: 13))
                  .foregroundColor(theme.muted.color)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(Text("\(draft.text) を消す"))
            }
          }
        }

        HStack(spacing: 8) {
          Button {
            onSend(store.takeAll(for: sessionKey))
          } label: {
            Text("戻ったら送る")
              .font(MTFont.ui(13, .medium))
              .foregroundColor(theme.bg.color)
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .background(Capsule().fill(theme.ok.color))
          }
          .buttonStyle(.plain)

          Button {
            store.discardAll(for: sessionKey)
          } label: {
            Text("破棄")
              .font(MTFont.ui(13, .medium))
              .foregroundColor(theme.sub.color)
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .background(Capsule().stroke(theme.line.color, lineWidth: 1))
          }
          .buttonStyle(.plain)
          Spacer()
        }
      }
      .padding(12)
      .background(RoundedRectangle(cornerRadius: 12).fill(theme.raised.color))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.bad.color.opacity(0.5), lineWidth: 1))
    }
  }
}

/// ターミナルに重ねるドラフトカードの置き場（SpaceController から使う）
struct MTDraftOverlayView: View {
  let onSend: ([String]) -> Void

  @ObservedObject private var store = MTDraftStore.shared
  @ObservedObject private var stateCenter = MTSessionStateCenter.shared

  var body: some View {
    VStack {
      Spacer()
      if let key = stateCenter.currentKey, store.count(for: key) > 0 {
        MTDraftCardView(sessionKey: key, onSend: onSend)
          .padding(.horizontal, 12)
          .padding(.bottom, 12)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.25), value: store.drafts.count)
  }
}
