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

/// この端末の名前。ローカルシェルのタブ名・プロンプトに使う。
/// iOS 16 以降は OS の制限で機種名（"iPhone" 等）になることがある。
@objc public class MTDeviceInfo: NSObject {
  @objc public static var name: String {
    let n = UIDevice.current.name
    return n.isEmpty ? UIDevice.current.model : n
  }

  /// ローカルシェルのプロンプト（例「iPhone ~ 」）
  @objc public static var localPrompt: String {
    "\(name) ~ "
  }
}
