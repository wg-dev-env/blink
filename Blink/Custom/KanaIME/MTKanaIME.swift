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
import KanaKanjiConverterModuleWithDefaultDictionary

/// アプリ内かな漢字変換（S24、13 §6）。
/// 外付けキーボードでは iOS のキーボード拡張（azooKey 等）が使えないため、
/// AzooKeyKanaKanjiConverter をアプリに組み込み、打鍵を `SmarterTermInput.onOut` で
/// 横取りしてかな漢字変換する。未確定文字列は端末に書かず候補バーにだけ表示し、
/// 確定文字列のみ端末へ書く（hterm の composition 経路のバグ群を踏まない。12 §I-1〜I-8）。
///
/// 利用前提: iOS 側のハードウェアキーボード入力モードは ABC（英語）にする。
/// 日本語（Apple IME）が生きている間は二重変換になるため自動で OFF にする。
final class MTKanaIME: ObservableObject {
  static let shared = MTKanaIME()

  /// onOut での打鍵 1 件の裁き
  enum Decision {
    case passthrough     // 従来どおり端末へ
    case swallow         // IME が消費（端末へ書かない）
    case output(String)  // 確定文字列に差し替えて端末へ
  }

  /// 切替キーの設定値（UserDefaults）
  enum ToggleKey: String, CaseIterable, Identifiable {
    case off        // アプリ内 IME を使わない
    case ctrlSpace  // Ctrl+Space（NUL）で切替。かな/英数キーも有効
    var id: String { rawValue }
    var label: String {
      switch self {
      case .off: return "使わない"
      case .ctrlSpace: return "Ctrl+Space で切替"
      }
    }
  }
  static let toggleKeyDefaultsKey = "MTKanaIMEToggleKey"

  // MARK: - UI へ公開する状態（候補バー・ピルが観測する）

  @Published private(set) var active = false
  /// 未確定のひらがな（ローマ字は ComposingText が逐次変換）
  @Published private(set) var composing = ""
  /// 変換候補（変換中のみ非空）
  @Published private(set) var candidates: [String] = []
  @Published private(set) var selectedIndex = 0
  /// 候補バーを出すべきか
  var barVisible: Bool { active && (!composing.isEmpty || !candidates.isEmpty) }

  // MARK: - 内部状態

  private var composingText = ComposingText()
  private var lastResults: [Candidate] = []
  private var converter: KanaKanjiConverter? = nil
  private var systemIsJapanese = false

  private init() {
    #if BLINK_PUBLISHING_OPTION_DEVELOPER
    // シミュレータ検証用（S24）: 切替キーが HID 注入できないため、
    // `simctl launch <udid> com.wgdevenv.moshterm -MTKanaIMEAutoOn YES` で起動時から ON にできる
    if UserDefaults.standard.bool(forKey: "MTKanaIMEAutoOn") {
      DispatchQueue.main.async { self.activate() }
    }
    #endif
  }

  var toggleKey: ToggleKey {
    ToggleKey(rawValue: UserDefaults.standard.string(forKey: Self.toggleKeyDefaultsKey) ?? "")
      ?? .ctrlSpace
  }

  // MARK: - 変換エンジン

  /// 学習データの保存先（アプリコンテナ内。再起動後も効く）
  private static func memoryDirectory() -> URL {
    let base = (try? FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("KanaIME/memory", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private lazy var options: ConvertRequestOptions = {
    let mem = Self.memoryDirectory()
    return ConvertRequestOptions(
      N_best: 9,
      requireJapanesePrediction: false,
      requireEnglishPrediction: false,
      keyboardLanguage: .ja_JP,
      learningType: .inputAndOutput,
      memoryDirectoryURL: mem,
      sharedContainerURL: mem,
      textReplacer: .empty,
      specialCandidateProviders: nil,
      metadata: nil
    )
  }()

  /// 初回のみ同期で生成する（実測: 初期化 19ms＋初回変換 226ms。IME ON 後の最初の変換時だけ）
  private func ensureConverter() -> KanaKanjiConverter {
    if let converter { return converter }
    let c = KanaKanjiConverter.withDefaultDictionary()
    converter = c
    return c
  }

  /// 学習のリセット（設定画面から）
  func resetLearning() {
    ensureConverter().resetMemory()
  }

  // MARK: - ON / OFF

  func toggle() { active ? deactivate() : activate() }

  func activate() {
    guard toggleKey != .off else { return }
    // Apple IME（日本語）が生きている間は二重変換になるため有効化しない
    guard !systemIsJapanese else { return }
    guard !active else { return }
    active = true
    MTInputModeCenter.shared.setInAppKana(true)
  }

  func deactivate() {
    guard active else { return }
    clearComposition()
    active = false
    MTInputModeCenter.shared.setInAppKana(false)
  }

  /// SmarterTermInput.reportLang から。iOS 側が日本語になったら自動 OFF（二重変換防止）
  func systemLangChanged(_ lang: String) {
    systemIsJapanese = lang.hasPrefix("ja")
    if systemIsJapanese && active {
      deactivate()
    }
  }

  /// JIS 外付けキーボードのかな（Lang1）/英数（Lang2）キー（KBWebView.pressesBegan から）
  func hardwareKanaKey(kana: Bool) {
    guard toggleKey != .off else { return }
    kana ? activate() : deactivate()
  }

  // MARK: - 打鍵の裁き（SmarterTermInput.onOut から。メインスレッド）

  func handle(_ data: String) -> Decision {
    // 切替キー: Ctrl+Space は端末では NUL（^@）として届く
    if toggleKey == .ctrlSpace && data == "\u{00}" {
      toggle()
      return .swallow
    }
    guard active else { return .passthrough }

    let converting = !candidates.isEmpty

    // --- 変換中（候補選択） ---
    if converting {
      switch data {
      case " ", "\t", "\u{1B}[C", "\u{1B}OC":   // 次候補（Space / Tab / →）
        selectedIndex = (selectedIndex + 1) % candidates.count
        return .swallow
      case "\u{1B}[Z", "\u{1B}[D", "\u{1B}OD":  // 前候補（Shift-Tab / ←）
        selectedIndex = (selectedIndex + candidates.count - 1) % candidates.count
        return .swallow
      case "\r":                                 // 確定
        return commitSelected()
      case "\u{7F}", "\u{1B}":                   // 変換を取り消してひらがな編集へ戻る
        candidates = []
        lastResults = []
        selectedIndex = 0
        return .swallow
      default:
        if isRomajiInput(data) {
          // 選択中の候補を確定してから、新しい入力を始める
          let committed = commitSelectedText()
          feedRomaji(data)
          return committed.isEmpty ? .swallow : .output(committed)
        }
        // それ以外（Ctrl 系・矢印など）: 選択中の候補を確定し、キー自体は端末へ通す
        let committed = commitSelectedText()
        return .output(committed + data)
      }
    }

    // --- ひらがな編集中 ---
    if !composing.isEmpty {
      switch data {
      case " ":                                  // 変換開始
        startConversion()
        return .swallow
      case "\r":                                 // ひらがなのまま確定
        let text = composing
        clearComposition()
        return .output(text)
      case "\u{7F}":                             // 1 文字削除
        composingText.deleteBackwardFromCursorPosition(count: 1)
        composing = composingText.convertTarget
        if composing.isEmpty { clearComposition() }
        return .swallow
      case "\u{1B}":                             // 全消去（IME は ON のまま）
        clearComposition()
        return .swallow
      default:
        if isRomajiInput(data) {
          feedRomaji(data)
          return .swallow
        }
        // 制御キー（Ctrl-C 等）・エスケープシーケンス・その他の文字:
        // 未確定は保持したまま素通しする（^C を絶対に飲み込まない。12 §E-6 の教訓）
        return .passthrough
      }
    }

    // --- IME ON・未確定なし ---
    if isRomajiInput(data) {
      feedRomaji(data)
      return .swallow
    }
    return .passthrough
  }

  // MARK: - 内部処理

  /// ローマ字入力として受けるか（英字と、かな入力で使う長音符）
  private func isRomajiInput(_ data: String) -> Bool {
    guard data.count == 1, let scalar = data.unicodeScalars.first else { return false }
    return (0x41...0x5A).contains(scalar.value)    // A-Z
      || (0x61...0x7A).contains(scalar.value)      // a-z
      || (!composing.isEmpty && data == "-")       // ー（編集中のみ）
  }

  private func feedRomaji(_ data: String) {
    composingText.insertAtCursorPosition(data, inputStyle: .roman2kana)
    composing = composingText.convertTarget
    MTInputModeCenter.shared.setComposing(true)
  }

  /// 候補バーに出す最大数（mainResults は予測含め数百件返るため切る）
  private static let maxCandidates = 9

  private func startConversion() {
    // 末尾の未解決 "n" は「ん」として確定してから変換する（kanjihenkan → かんじへんかん）
    if composingText.convertTarget.hasSuffix("n") {
      composingText.insertAtCursorPosition("n", inputStyle: .roman2kana)
      composing = composingText.convertTarget
    }
    let result = ensureConverter().requestCandidates(composingText, options: options)
    lastResults = Array(result.mainResults.prefix(Self.maxCandidates))
    candidates = lastResults.map(\.text)
    selectedIndex = 0
  }

  /// 選択中候補のテキストを取り出し、学習を確定して状態を片付ける
  private func commitSelectedText() -> String {
    guard selectedIndex < candidates.count else { return "" }
    let text = candidates[selectedIndex]
    if selectedIndex < lastResults.count, let converter {
      let candidate = lastResults[selectedIndex]
      converter.setCompletedData(candidate)
      converter.updateLearningData(candidate)
    }
    clearComposition()
    return text
  }

  private func commitSelected() -> Decision {
    let text = commitSelectedText()
    return text.isEmpty ? .swallow : .output(text)
  }

  private func clearComposition() {
    composingText = ComposingText()
    composing = ""
    candidates = []
    lastResults = []
    selectedIndex = 0
    converter?.stopComposition()
    MTInputModeCenter.shared.setComposing(false)
  }
}
