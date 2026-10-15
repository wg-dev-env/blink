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

import UIKit

/// 親指ダイヤル（07 #06）。
///
/// 指を円を描くように動かすと 1 目盛りごとにキーを送る。縦回し（上下）は ↑↓ で
/// シェルの履歴送りになり、横回し（左右）は ←→ でカーソル移動になる。
/// 指を離したとき回していなければ Return（押し込み相当）。
/// 1 目盛りごとに触覚フィードバックを返す。
class KBKeyViewDial: KBKeyView {
  private let _ring = CAShapeLayer()
  private let _notch = CAShapeLayer()
  private let _glyph = UIImageView(
    image: UIImage(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
      ?? UIImage(systemName: "arrow.triangle.2.circlepath"))

  private var _center: CGPoint = .zero
  private var _lastAngle: CGFloat? = nil
  /// 目盛りを跨いだ量（1.0 で 1 キー送る）
  private var _accumulated: CGFloat = 0
  private var _didRotate = false
  /// 回し始めの向き（縦回し = 履歴、横回し = カーソル）
  private var _vertical = true

  private let _haptics = UISelectionFeedbackGenerator()

  /// 1 目盛りの角度（ラジアン）。12 分割
  private static let notch: CGFloat = .pi / 6

  override init(key: KBKey, keyDelegate: KBKeyViewDelegate) {
    super.init(key: key, keyDelegate: keyDelegate)

    isAccessibilityElement = true
    accessibilityLabel = "ダイヤル"
    accessibilityHint = "回すと矢印キー、タップで Return"

    _ring.fillColor = UIColor.clear.cgColor
    _ring.strokeColor = UIColor.label.withAlphaComponent(0.35).cgColor
    _ring.lineWidth = 1.5
    layer.addSublayer(_ring)

    _notch.fillColor = UIColor.label.withAlphaComponent(0.8).cgColor
    layer.addSublayer(_notch)

    _glyph.contentMode = .center
    _glyph.tintColor = UIColor.label.withAlphaComponent(0.5)
    _glyph.preferredSymbolConfiguration = .init(
      pointSize: keyDelegate.kbSizes.key.fonts.symbol * 0.8, weight: .regular)
    addSubview(_glyph)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    let keyBounds = bounds.inset(by: keyDelegate.kbSizes.key.insets.key)
    _center = CGPoint(x: keyBounds.midX, y: keyBounds.midY)
    let radius = min(keyBounds.width, keyBounds.height) * 0.38

    _ring.path = UIBezierPath(
      arcCenter: _center, radius: radius,
      startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath

    // 現在の向きを示す小さな点
    let angle = _lastAngle ?? -.pi / 2
    let dot = CGPoint(x: _center.x + cos(angle) * radius,
                      y: _center.y + sin(angle) * radius)
    _notch.path = UIBezierPath(
      arcCenter: dot, radius: 2.5,
      startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath

    _glyph.frame = CGRect(x: _center.x - 10, y: _center.y - 10, width: 20, height: 20)
  }

  // MARK: - 操作

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first else { return }
    super.touchesBegan(touches, with: event)

    _haptics.prepare()
    _didRotate = false
    _accumulated = 0
    _lastAngle = _angle(of: touch)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesMoved(touches, with: event)
    guard let touch = touches.first, let last = _lastAngle else { return }

    let point = touch.location(in: self)
    let angle = _angle(of: touch)

    // 最初の動きで、縦回し（履歴）か横回し（カーソル）かを決める
    if !_didRotate {
      let dx = abs(point.x - _center.x)
      let dy = abs(point.y - _center.y)
      _vertical = dy >= dx
    }

    var delta = angle - last
    // -π..π に畳む（0 をまたぐときの飛びを防ぐ）
    if delta > .pi { delta -= .pi * 2 }
    if delta < -.pi { delta += .pi * 2 }

    _accumulated += delta
    _lastAngle = angle

    while abs(_accumulated) >= Self.notch {
      let forward = _accumulated > 0
      _accumulated -= forward ? Self.notch : -Self.notch
      _didRotate = true
      _emit(forward: forward)
    }

    setNeedsLayout()
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    // 回していなければ押し込み = Return
    if !_didRotate {
      _sendReturn()
      UIDevice.current.playInputClick()
    }
    _lastAngle = nil
    _accumulated = 0
    super.touchesEnded(touches, with: event)
    setNeedsLayout()
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    _lastAngle = nil
    _accumulated = 0
    _didRotate = false
    super.touchesCancelled(touches, with: event)
  }

  // MARK: - 中身

  /// Return は KBKeyValue に無いので、キー入力へ直接 Return キーを報告する
  private func _sendReturn() {
    guard let input = KBTracker.shared.input else { return }
    input.reportPress(UIKeyModifierFlags(rawValue: 0), keyId: KeyCode.return.id)
  }

  private func _angle(of touch: UITouch) -> CGFloat {
    let point = touch.location(in: self)
    return atan2(point.y - _center.y, point.x - _center.x)
  }

  /// 1 目盛りぶん送る。時計回り = 次（↓ / →）、反時計回り = 前（↑ / ←）
  private func _emit(forward: Bool) {
    let value: KBKeyValue
    if _vertical {
      value = forward ? .down : .up
    } else {
      value = forward ? .right : .left
    }
    _haptics.selectionChanged()
    _haptics.prepare()
    keyDelegate.keyViewTriggered(keyView: self, value: value)
  }

  override func turnOff() {
    super.turnOff()
    _lastAngle = nil
    _accumulated = 0
    _didRotate = false
  }
}
