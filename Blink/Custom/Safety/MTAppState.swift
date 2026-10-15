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

import Foundation
import UIKit

/// アプリが前面にあるかを、どのスレッドからでも安全に見られるようにする。
///
/// セッションのコマンドはバックグラウンドのキューで走るため、そこから
/// `UIApplication.shared.applicationState` は触れない。シーンの通知で
/// 更新した値をここに持っておく。
@objc public class MTAppState: NSObject {
  @objc public private(set) static var isForeground: Bool = true

  @objc public static func startObserving() {
    let center = NotificationCenter.default
    center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { _ in
      isForeground = true
    }
    center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { _ in
      isForeground = false
    }
    center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
      isForeground = false
    }
    center.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main) { _ in
      isForeground = true
    }
  }
}
