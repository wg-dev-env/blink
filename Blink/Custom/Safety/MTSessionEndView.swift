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

/// 接続が終わったセッションの置き場。
/// exit した直後は `blink>` のローカルプロンプトに戻るが、それだけでは
/// 「終わったのか固まったのか」が分からないため、案内を重ねて出す。
final class MTSessionEndCenter: ObservableObject {
  static let shared = MTSessionEndCenter()

  struct Ended {
    let command: String
    let alias: String?
  }

  /// 終了の案内を出しているセッション
  @Published private(set) var ended: [UUID: Ended] = [:]

  private init() {}

  func note(command: String, for key: UUID) {
    let alias = MTHostContext.shared.alias(for: key)
    ended[key] = Ended(command: command, alias: alias)
  }

  func clear(for key: UUID) {
    ended.removeValue(forKey: key)
  }

  func ended(for key: UUID?) -> Ended? {
    guard let key else { return nil }
    return ended[key]
  }
}

/// 接続が終わったときの案内（ターミナルに重ねる）
struct MTSessionEndView: View {
  let onReconnect: (String) -> Void
  let onNewConnection: () -> Void
  let onCloseTab: () -> Void

  @ObservedObject private var center = MTSessionEndCenter.shared
  @ObservedObject private var stateCenter = MTSessionStateCenter.shared
  @ObservedObject private var themeStore = MTThemeStore.shared

  private var theme: MTTheme { themeStore.currentTheme }

  var body: some View {
    if let key = stateCenter.currentKey, let ended = center.ended(for: key) {
      VStack(spacing: 16) {
        VStack(spacing: 6) {
          Image(systemName: "powerplug")
            .font(.system(size: 26, weight: .light))
            .foregroundColor(theme.muted.color)
          Text("接続が終了しました")
            .font(MTFont.ui(17, .bold))
            .foregroundColor(theme.text.color)
          if let alias = ended.alias {
            Text(alias)
              .font(MTFont.mono(13))
              .foregroundColor(theme.sub.color)
          }
          Text("このタブはローカルシェルに戻っています。そのまま使うこともできます。")
            .font(MTFont.ui(12))
            .foregroundColor(theme.muted.color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }

        VStack(spacing: 8) {
          if !ended.command.isEmpty {
            Button {
              center.clear(for: key)
              onReconnect(ended.command)
            } label: {
              Label("もう一度つなぐ", systemImage: "arrow.clockwise")
                .font(MTFont.ui(14, .medium))
                .foregroundColor(theme.bg.color)
                .frame(maxWidth: 260)
                .padding(.vertical, 10)
                .background(Capsule().fill(theme.ok.color))
            }
            .buttonStyle(.plain)
          }

          Button {
            center.clear(for: key)
            onNewConnection()
          } label: {
            Label("別の接続先を選ぶ", systemImage: "plus")
              .font(MTFont.ui(14, .medium))
              .foregroundColor(theme.accent.color)
              .frame(maxWidth: 260)
              .padding(.vertical, 10)
              .background(Capsule().stroke(theme.accent.color.opacity(0.6), lineWidth: 1))
          }
          .buttonStyle(.plain)

          HStack(spacing: 18) {
            Button("ローカルシェルを使う") {
              center.clear(for: key)
            }
            .font(MTFont.ui(13))
            .foregroundColor(theme.sub.color)

            Button("タブを閉じる") {
              center.clear(for: key)
              onCloseTab()
            }
            .font(MTFont.ui(13))
            .foregroundColor(theme.bad.color)
          }
          .buttonStyle(.plain)
          .padding(.top, 2)
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(theme.bg.color.opacity(0.94))
      .transition(.opacity)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(Text("接続が終了しました"))
    }
  }
}
