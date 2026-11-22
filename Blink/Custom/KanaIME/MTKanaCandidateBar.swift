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

/// アプリ内かな漢字変換の候補バー（S24 最小版。意匠の作り込みは S25 / 06 §5.2）。
/// 未確定のひらがなと変換候補を表示する。表示専用（操作はキーボードで行う）。
/// キーボード上端にアンカーして出す（SpaceController._mtActivateKanaOverlay）。
struct MTKanaCandidateBar: View {
  @ObservedObject private var ime = MTKanaIME.shared
  @ObservedObject private var themeStore = MTThemeStore.shared

  private var theme: MTTheme { themeStore.currentTheme }

  var body: some View {
    VStack {
      Spacer(minLength: 0)
      if ime.barVisible {
        bar
          .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.12), value: ime.barVisible)
  }

  private var bar: some View {
    VStack(alignment: .leading, spacing: 6) {
      // 未確定のひらがな（確定するまで端末には書かれない）
      Text(ime.composing.isEmpty && !ime.candidates.isEmpty
           ? ime.candidates[min(ime.selectedIndex, ime.candidates.count - 1)]
           : ime.composing)
        .font(MTFont.ui(16, .medium))
        .foregroundColor(theme.accent.color)
        .underline()
        .lineLimit(1)

      if !ime.candidates.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          ScrollViewReader { proxy in
            HStack(spacing: 6) {
              ForEach(Array(ime.candidates.enumerated()), id: \.offset) { index, text in
                HStack(spacing: 4) {
                  Text("\(index + 1)")
                    .font(MTFont.ui(11, .regular))
                    .foregroundColor(theme.sub.color)
                  Text(text)
                    .font(MTFont.ui(15, .medium))
                    .foregroundColor(index == ime.selectedIndex ? theme.bg.color : theme.text.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                  RoundedRectangle(cornerRadius: 6)
                    .fill(index == ime.selectedIndex ? theme.accent.color : theme.raised.color)
                )
                .id(index)
              }
            }
            .onChange(of: ime.selectedIndex) { _, newValue in
              withAnimation(.easeInOut(duration: 0.12)) {
                proxy.scrollTo(newValue, anchor: .center)
              }
            }
          }
        }
      } else {
        Text("Space: 変換 / Enter: 確定 / Esc: 取消")
          .font(MTFont.ui(11, .regular))
          .foregroundColor(theme.sub.color)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(theme.raised.color.opacity(0.96))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(theme.line.color, lineWidth: 1)
    )
    .padding(.horizontal, 12)
    .padding(.bottom, 6)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(accessibilityText))
  }

  private var accessibilityText: String {
    if ime.candidates.isEmpty {
      return "かな入力中: \(ime.composing)"
    }
    let selected = ime.candidates[min(ime.selectedIndex, ime.candidates.count - 1)]
    return "変換候補 \(ime.selectedIndex + 1) / \(ime.candidates.count): \(selected)"
  }
}
