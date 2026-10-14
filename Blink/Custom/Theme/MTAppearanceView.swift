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

/// 設定 › 外観。配色（4 列 × 2 段の見本カード、06 §3）と外観モード。
/// S1 の仮置き画面。正式な設定画面の構成は S8 で 06 §6.5 に揃える。
struct MTAppearanceView: View {
  @ObservedObject private var store = MTThemeStore.shared

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

  var body: some View {
    List {
      Section {
        LazyVGrid(columns: columns, spacing: 12) {
          ForEach(MTTheme.all) { theme in
            Button {
              store.select(theme)
            } label: {
              MTThemeCard(theme: theme, isSelected: store.selectedThemeID == theme.id)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.vertical, 6)

        if let theme = store.selectedTheme {
          Text(theme.summary)
            .font(.footnote)
            .foregroundColor(.secondary)
        }
      } header: {
        Text("配色")
      } footer: {
        Text("選ぶと開いているセッションにもすぐ反映されます。")
      }

      Section("外観モード") {
        Picker("外観モード", selection: $store.appearanceMode) {
          Text("システムに合わせる").tag(MTThemeStore.AppearanceMode.system)
          Text("常にテーマどおり").tag(MTThemeStore.AppearanceMode.theme)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
    }
    .navigationTitle("外観")
  }
}

/// テーマの見本カード。地色・文字・状態色 3 点・accent を一目で見せる。
private struct MTThemeCard: View {
  let theme: MTTheme
  let isSelected: Bool

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        RoundedRectangle(cornerRadius: 10)
          .fill(theme.bg.color)
        VStack(spacing: 5) {
          Text("Aあ")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(theme.text.color)
          HStack(spacing: 4) {
            Circle().fill(theme.ok.color).frame(width: 6, height: 6)
            Circle().fill(theme.warn.color).frame(width: 6, height: 6)
            Circle().fill(theme.bad.color).frame(width: 6, height: 6)
          }
          RoundedRectangle(cornerRadius: 1)
            .fill(theme.accent.color)
            .frame(width: 22, height: 3)
        }
      }
      .frame(height: 64)
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(isSelected ? theme.accent.color : theme.line.color,
                  lineWidth: isSelected ? 2 : 1)
      )

      Text(theme.name)
        .font(.system(size: 12))
        .foregroundColor(.primary)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("配色「\(theme.name)」。\(theme.summary)"))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
