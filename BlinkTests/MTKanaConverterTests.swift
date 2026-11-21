//////////////////////////////////////////////////////////////////////////////////
//
// S23 PoC: AzooKeyKanaKanjiConverter の導入判定用テスト
//
// 計測対象（13_アプリ内かな漢字変換（AzooKey）調査 §6.6）:
//   - ローマ字入力 → 変換候補が取得できること（正しさ）
//   - 初期化時間・初回変換・定常変換レイテンシ（目安: 定常 20ms 以内）
//   - 変換前後の常駐メモリ増（目安: +60MB 以内）
// 結果は標準出力に [S23] プレフィックスで出す（xcodebuild ログから回収する）。
//
//////////////////////////////////////////////////////////////////////////////////

import XCTest
import KanaKanjiConverterModuleWithDefaultDictionary

class MTKanaConverterTests: XCTestCase {

  // 学習は PoC では無効。保存先はテンポラリを渡す（書き込まれない想定）
  private func makeOptions() -> ConvertRequestOptions {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("s23-kana-memory", isDirectory: true)
    return ConvertRequestOptions(
      N_best: 10,
      requireJapanesePrediction: false,
      requireEnglishPrediction: false,
      keyboardLanguage: .ja_JP,
      learningType: .nothing,
      memoryDirectoryURL: tmp,
      sharedContainerURL: tmp,
      textReplacer: .empty,
      specialCandidateProviders: nil,
      metadata: nil
    )
  }

  // 現プロセスの常駐メモリ（phys_footprint）を MB で返す
  private func memoryFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return -1 }
    return Double(info.phys_footprint) / 1_048_576.0
  }

  private func convert(_ romaji: String, converter: KanaKanjiConverter, options: ConvertRequestOptions) -> [String] {
    var composing = ComposingText()
    composing.insertAtCursorPosition(romaji, inputStyle: .roman2kana)
    let result = converter.requestCandidates(composing, options: options)
    return result.mainResults.map(\.text)
  }

  func testConversionAndMeasure() {
    let memBefore = memoryFootprintMB()

    // 1) 初期化時間
    let t0 = Date()
    let converter = KanaKanjiConverter.withDefaultDictionary()
    let initMs = Date().timeIntervalSince(t0) * 1000
    let options = makeOptions()

    // 2) 初回変換（辞書の遅延ロード込み）
    let t1 = Date()
    let first = convert("kyouhaiitenkidesune", converter: converter, options: options)
    let firstMs = Date().timeIntervalSince(t1) * 1000

    // 3) 正しさ: 上位候補に期待の変換が含まれる
    print("[S23] candidates(kyouhaiitenkidesune): \(first.prefix(5))")
    XCTAssertFalse(first.isEmpty, "変換候補が空")
    XCTAssertTrue(
      first.contains { $0.contains("今日") && $0.contains("天気") },
      "上位候補に『今日…天気…』が無い: \(first.prefix(10))"
    )

    // 代表的な文をもう少し
    let samples = [
      "watashinonamaehatanakadesu",
      "mosshudesessyonngakirenai",
      "tamuxnosesshonwokiru",
      "nihongonyuuryokunotesuto",
    ]
    for s in samples {
      let r = convert(s, converter: converter, options: options)
      print("[S23] \(s) -> \(r.prefix(3))")
      XCTAssertFalse(r.isEmpty, "候補が空: \(s)")
    }

    // 4) 定常レイテンシ: 20 回変換の平均と最大
    let phrases = (0..<20).map { i in
      ["kyouhaiitenki", "arigatougozaimasu", "sakujoshimasu", "setsuzokuchuudesu", "kanjihenkan"][i % 5]
    }
    var times: [Double] = []
    for p in phrases {
      let t = Date()
      _ = convert(p, converter: converter, options: options)
      times.append(Date().timeIntervalSince(t) * 1000)
    }
    let avgMs = times.reduce(0, +) / Double(times.count)
    let maxMs = times.max() ?? 0

    let memAfter = memoryFootprintMB()

    print(String(format: "[S23] init: %.1f ms / first convert: %.1f ms", initMs, firstMs))
    print(String(format: "[S23] steady convert: avg %.1f ms, max %.1f ms (n=%d)", avgMs, maxMs, times.count))
    print(String(format: "[S23] memory footprint: before %.1f MB -> after %.1f MB (delta %.1f MB)", memBefore, memAfter, memAfter - memBefore))

    // 判定ゲートの目安（13 §5）。超えても即 fail にせず記録を主目的とするが、
    // 大幅超過（2倍）は fail にして気づけるようにする
    XCTAssertLessThan(avgMs, 40, "定常変換が目安 20ms の2倍を超過")
    XCTAssertLessThan(memAfter - memBefore, 120, "メモリ増が目安 60MB の2倍を超過")
  }
}
