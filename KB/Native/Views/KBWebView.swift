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


import UIKit

class BlinkCommand: UIKeyCommand {
  var bindingAction: KeyBindingAction = .none
}

class KBWebView: KBWebViewBase {
  
  private var _loaded = false
  private(set) var webViewReady = false
  private(set) var blinkKeyCommands: [BlinkCommand] = []
  private(set) var allBlinkKeyCommands: [BlinkCommand] = []
  
  func configure(_ cfg: KBConfig) {
    _buildCommands(cfg)

    guard
      let data = try? JSONEncoder().encode(cfg),
      let json = String(data: data, encoding: .utf8)
    else {
      return
    }
    report("config", arg: json as NSString)
  }
  
  func _buildCommands(_ cfg: KBConfig) {
    
    self.blinkKeyCommands.removeAll()
    self.allBlinkKeyCommands.removeAll()
    
    cfg.shortcuts.forEach { shortcut in
      guard !shortcut.isCleared else { return }
      let cmd = BlinkCommand(
        title: "",
        image: nil,
        action: #selector(SpaceController._onBlinkCommand(_:)),
        input: shortcut.input,
        modifierFlags: shortcut.modifiers,
        propertyList: nil
      )
      cmd.bindingAction = shortcut.action
      
      allBlinkKeyCommands.append(cmd)
      
      if !shortcut.action.isCommand {
        blinkKeyCommands.append(cmd)
      }
    }
  }
  
  
  override var editingInteractionConfiguration: UIEditingInteractionConfiguration {
    return .none
  }
  
  func matchCommand(input: String, flags: UIKeyModifierFlags) -> (UIKeyCommand, UIResponder)? {
    var result: (UIKeyCommand, UIResponder)? = nil
    
    var iterator: UIResponder? = self
    
    // try first on space controller
    let cmd = allBlinkKeyCommands.first(
      where: {
        $0.input == input && $0.modifierFlags == flags
      }
    )
    
    if let cmd = cmd {
      while let responder = iterator {
        if let _ = responder as? SpaceController,
           let action = cmd.action,
           responder.canPerformAction(action, withSender: self) {
          return (cmd, responder)
        }
        iterator = responder.next
      }
    }
    
    iterator = self
    
    while let responder = iterator {
      if let cmd = responder.keyCommands?.first(
        where: {
          $0.input == input && $0.modifierFlags == flags
        }),
         let action = cmd.action,
         responder.canPerformAction(action, withSender: self)
      {
        result = (cmd, responder)
      }
      iterator = responder.next
    }

    return result
  }
  
  /// キー入力の確認に出す補足。かな漢字変換の設定と、切り替えに使ったかを添える
  private static func kanaProbeNote(_ key: UIKey, consumed: Bool) -> String {
    var parts = ["かな漢字変換=\(MTKanaIME.shared.engine.label)"]
    if key.keyCode == .keyboardSpacebar, key.modifierFlags.contains(.control) {
      parts.append("iOS に日本語キーボード=\(MTKanaIME.shared.systemHasJapaneseKeyboard ? "有" : "無")")
    }
    parts.append(consumed ? "切り替えに使った" : "切り替えには使っていない")
    return parts.joined(separator: " ／ ")
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    // S24: JIS 外付けキーボードのかな（Lang1）/英数（Lang2）キーでアプリ内 IME を切り替える。
    // 変換（International2）もかな ON として扱う。
    for press in presses {
      guard let key = press.key else { continue }
      #if BLINK_PUBLISHING_OPTION_DEVELOPER
      // S23 PoC: キーが届くかの実機検証ログ（Xcode コンソールで [S23-kana] を確認）
      if key.keyCode == .keyboardLANG1 || key.keyCode == .keyboardLANG2 ||
         key.keyCode == .keyboardInternational2 /* 変換 */ || key.keyCode == .keyboardInternational5 /* 無変換 */ {
        print("[S23-kana] pressesBegan keyCode=\(key.keyCode.rawValue) chars=\(key.characters.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: ","))")
      }
      #endif
      // 切り替えに使ったキーはここで飲み込む。super へ流すと WebView 側の入力経路に
      // 渡り、文字としても端末に届く（JIS キーボードを ABC レイアウトで使うと、
      // かなキーが別の文字として解釈されて「,また,」のように混ざる）
      var consumedByKanaIME = false
      if key.keyCode == .keyboardLANG1 || key.keyCode == .keyboardInternational2 {
        consumedByKanaIME = MTKanaIME.shared.hardwareKanaKey(kana: true)
      } else if key.keyCode == .keyboardLANG2 || key.keyCode == .keyboardInternational5 {
        consumedByKanaIME = MTKanaIME.shared.hardwareKanaKey(kana: false)
      } else if key.keyCode == .keyboardSpacebar,
                key.modifierFlags.contains(.control) {
        // 端末向けの NUL に化けない構成でも切り替えられるよう UIKit 側でも受ける。
        // Ctrl+Shift+Space は常に受ける（iPadOS は使わない）。Ctrl+Space は、iOS に
        // 日本語キーボードが入っていると入力ソース切替に使われるので譲る
        if key.modifierFlags.contains(.shift) || !MTKanaIME.shared.systemHasJapaneseKeyboard {
          consumedByKanaIME = MTKanaIME.shared.hardwareToggleKey()
        }
      }
      // 打鍵が届いているかの記録（診断 › キー入力の確認。既定 OFF）
      MTKeyProbe.shared.note(key, note: Self.kanaProbeNote(key, consumed: consumedByKanaIME))

      if consumedByKanaIME { return }
    }
    for press in presses {
      if let key = press.key, key.keyCode == .keyboardLeftGUI || key.keyCode == .keyboardRightGUI,
         let termView = superview as? TermView {
        termView.setCmdKeyPressed(true)
      }
    }

    guard
      let key = presses.first?.key,
      let (cmd, responder) = matchCommand(input: key.charactersIgnoringModifiers, flags: key.modifierFlags),
      let action = cmd.action
    else {
      if let key = presses.first?.key,
         key.keyCode.rawValue == 55,
         key.characters == "UIKeyInputEscape"
      {
        self.reportToolbarPress(key.modifierFlags.union(.command), keyId: "190:0")
        return
      }
      super.pressesBegan(presses, with: event)
      return
    }

    responder.perform(action, with: cmd)
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    for press in presses {
      if let key = press.key, key.keyCode == .keyboardLeftGUI || key.keyCode == .keyboardRightGUI,
         let termView = superview as? TermView {
        termView.setCmdKeyPressed(false)
      }
    }

    super.pressesEnded(presses, with: event)
  }
  
  func contentView() -> UIView? {
    scrollView.subviews.first
  }
  
  func disableTextSelectionView() {
    let subviews = scrollView.subviews
    guard
      subviews.count > 2,
      let v = subviews[1].subviews.first
    else {
      return
    }
    NotificationCenter.default.removeObserver(v)
  }
  
  override func ready() {
    webViewReady = true
    super.ready()
    configure(KBTracker.shared.loadConfig())
  }
  
  private func _loadKB() {
    let bundle = Bundle.init(for: KBWebView.self)
    guard
      let path = bundle.path(forResource: "kb", ofType: "html")
    else {
      return
    }
    let url = URL(fileURLWithPath: path)
    loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
  }
  
  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    if window != nil && !_loaded {
      _loaded = true
      _loadKB()
    }
  }
}
