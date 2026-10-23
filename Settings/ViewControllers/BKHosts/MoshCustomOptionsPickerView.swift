//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
//
// This file is part of Blink.
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
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////


import SwiftUI

extension BKMoshPrediction: Hashable {
  var label: String {
    switch self {
    case BKMoshPredictionAdaptive: return "自動（Adaptive）"
    case BKMoshPredictionAlways: return "常に（Always）"
    case BKMoshPredictionNever: return "しない（Never）"
    case BKMoshPredictionExperimental: return "積極的（Experimental）"
    case _: return ""
    }
  }

  /// 一覧の右側に出す短い名前（ホスト編集の行など）
  var shortLabel: String {
    switch self {
    case BKMoshPredictionAdaptive: return "自動"
    case BKMoshPredictionAlways: return "常に"
    case BKMoshPredictionNever: return "しない"
    case BKMoshPredictionExperimental: return "積極的"
    case _: return ""
    }
  }

  var hint: String {
    switch self {
    case BKMoshPredictionAdaptive:
      return "遅い回線のときだけ、打った文字を先に手元へ表示します（既定）。確定するまで下線が付きます。"
    case BKMoshPredictionAlways:
      return "回線の速さに関わらず、常に打った文字を先に手元へ表示します。遅い回線で一番軽く感じますが、速い回線では下線付きの予測文字が気になることがあります。"
    case BKMoshPredictionNever:
      return "先行表示をしません。サーバーから返ってきた文字だけを表示します。"
    case BKMoshPredictionExperimental:
      return "外れる可能性があっても積極的に先行表示します。"
    case _: return ""
    }
  }

  static var all: [BKMoshPrediction] {
    [
      BKMoshPredictionAdaptive,
      BKMoshPredictionAlways,
      BKMoshPredictionNever,
      BKMoshPredictionExperimental
    ]
  }
}

extension BKMoshExperimentalIP: Hashable {
  var label: String {
    switch self {
    case BKMoshExperimentalIPNone: return "なし（None）"
    case BKMoshExperimentalIPLocal: return "手元（Local）"
    case BKMoshExperimentalIPRemote: return "リモート（Remote）"
    case _: return ""
    }
  }
  
  var hint: String {
    switch self {
    case BKMoshExperimentalIPNone: return "IP の解決は SSH 接続から取得します（既定）。"
    case BKMoshExperimentalIPLocal: return "IP を手元で解決します。"
    case BKMoshExperimentalIPRemote: return "IP をリモート側で解決します。"
    case _: return ""
    }
  }

  static var all: [BKMoshExperimentalIP] {
    [
      BKMoshExperimentalIPNone,
      BKMoshExperimentalIPLocal,
      BKMoshExperimentalIPRemote,
    ]
  }
}

struct MoshCustomOptionsPickerView: View {
  @Binding var predictionValue: BKMoshPrediction
  @Binding var overwriteValue: Bool
  @Binding var experimentalIPValue: BKMoshExperimentalIP
  
  var body: some View {
    List {
      Section(header: Text("予測表示（Prediction）"), footer: Text(predictionValue.hint)) {
        ForEach(BKMoshPrediction.all, id: \.self) { value in
          HStack {
            Text(value.label).tag(value)
            Spacer()
            Checkmark(checked: predictionValue == value)
          }
          .contentShape(Rectangle())
          .onTapGesture { predictionValue = value }
        }
      }
      Section(footer: Text("先行表示を挿入ではなく上書きで行います（Prediction overwrites instead of inserting）。")) {
        HStack {
          Toggle("上書き（Overwrite）", isOn: $overwriteValue)
        }
      }
      Section(header: Text("実験的な IP 解決（Experimental IP）"), footer: Text(experimentalIPValue.hint)) {
        ForEach(BKMoshExperimentalIP.all, id: \.self) { value in
          HStack {
            Text(value.label).tag(value)
            Spacer()
            Checkmark(checked: experimentalIPValue == value)
          }
          .contentShape(Rectangle())
          .onTapGesture { experimentalIPValue = value }
        }
      }
    }
    .listStyle(InsetGroupedListStyle())
    .navigationTitle("Mosh Options")
  }
}
