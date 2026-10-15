////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2018 Blink Mobile Shell Project
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

#import <Foundation/Foundation.h>

#import "TermDevice.h"
#import "Session.h"
#import "TokioSignals.h"


@class MCPParams;
@class BlinkSSH;

// 64_MoshTerm: 接続（mosh/ssh）が終了したときに飛ぶ通知。userInfo に command / sessionKey
extern NSString * const MTRemoteSessionDidEndNotification;

@interface MCPSession : Session <TermDeviceReadlineListener>

@property (strong) MCPParams *sessionParams;
@property (readonly) dispatch_queue_t cmdQueue;
@property (strong) TokioSignals *tokioSignals;
// 64_MoshTerm: このセッションの識別子（TermController.meta.key の uuidString）。
// 接続終了の案内を正しいタブへ出すために使う
@property (copy) NSString *mtSessionKey;

- (void)registerSSHClient:(id __weak)sshClient;
- (void)unregisterSSHClient:(id __weak)sshClient;

- (void)enqueueCommand:(NSString *)cmd;
- (void)enqueueCommand:(NSString *)cmd skipHistoryRecord: (BOOL) skipHistoryRecord;
- (bool)isRunningCmd;

- (void)updateAllowedPaths;
- (void)setActiveSession;

@end
