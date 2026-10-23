'use strict';

hterm.defaultStorage = new lib.Storage.Memory();

window.fontSizeDetectionMethod = 'canvas';

function _postMessage(op, data) {
  window.webkit.messageHandlers.interOp.postMessage({op, data});
}

hterm.notify = function(params) {
  var def = (curr, fallback) => curr !== undefined ? curr : fallback;
  if (params === undefined || params === null) {
    params = {};
  }


  var title = def(params.title, window.document.title);
  if (!title)
    title = 'hterm';

  _postMessage('notify', {title, body: params.body})
}

hterm.Terminal.prototype.ringBell = function() {
  // Blink cursor on BEL character
  this.cursorNode_.style.backgroundColor = this.scrollPort_.getForegroundColor();
    
  setTimeout(() => this.restyleCursor_(), 200);
  
  _postMessage('ring-bell', null);
};

hterm.Terminal.prototype.copyStringToClipboard = function(content) {
  if (this.prefs_.get('enable-clipboard-notice')) {
    setTimeout(this.showOverlay.bind(this, hterm.notifyCopyMessage, 500), 200);
  }

  document.getSelection().removeAllRanges();
  _postMessage('copy', {content});
};

document.addEventListener('selectionchange', function() {
  _postMessage('selectionchange', term_getCurrentSelection());
});

hterm.Terminal.IO.prototype.sendString = function(string) {
  _postMessage('sendString', {string});
};

hterm.msg = function() {}; // TODO: show messages

function _colorComponents(colorStr) {
  if (!colorStr) {
    return [0, 0, 0]; // Default is black
  }

  return colorStr
    .replace(/[^0-9,]/g, '')
    .split(',')
    .map(s => parseInt(s));
}

// Before we fully load hterm. We set options here.
var _prefs = new hterm.PreferenceManager('blink');
var t = {prefs_: _prefs}; // <- `t` will become actual hterm instance after decorate.

function term_set(key, value) {
  _prefs.set(key, value);
}

function term_get(key) {
  return _prefs.get(key);
}

function term_setupDefaults() {
  term_set('copy-on-select', false);
  term_set('audible-bell-sound', '');
  term_set('receive-encoding', 'raw'); // we are UTF8
  term_set('allow-images-inline', true); // need to make it work
  term_set('scroll-wheel-may-send-arrow-keys', true)
}

function term_processKB(str) {
  if (!t.prompt) {
    return;
  }
  if (str) {
    t.prompt.processInput(str);
  }
}

function term_displayInput(str, display) {
  if (!t || !t.accessibilityReader_) {
    return;
  }
  
  t.accessibilityReader_.hasUserGesture = true;
  
  if (!display) {
    return;
  }
  
  if (str && !t.prompt._secure) {
    window.KeystrokeVisualizer.processInput(str);
  }
}


// MoshTerm: IME（かな漢字変換）の未確定文字の位置決めを修正する。
//
// 未確定文字は hterm_all.min.js に同梱された Blink 製キーボード層が持つ caret（div）に
// WebKit が直接描画し、位置は同層の _moveCaret が端末のカーソル位置から計算している。
// その実装に 2 つの欠陥がある。
//
//  (1) 最後の分岐（未確定文字が折り返す かつ カーソル行が 0 行目でない）で
//        o.style.top = `calc(var(--hterm-charsize-height) * ${a-1}`
//      と calc( の閉じ括弧が欠落している。不正な CSS 値は無視されるため直前に入れた
//      top:"auto" が残り、未確定文字の箱が意図しない位置（画面上端寄り）へ飛ぶ。
//      ＝「行の右端近くで長めの日本語を打つと変換中の表示が飛ぶ」の原因。
//
//  (2) 確定時（compositionend）は _moveCaret(確定文字列) の直後に _output が呼ばれるが、
//      _output は caret の中身（innerHTML）だけを消し、_moveCaret が入れた
//      top/left/right/background-color を戻さない。未確定文字が画面幅以上だった場合は
//      left:0/right:0 のままなので、カーソル色の帯が残る。
//
// hterm_all.min.js は minified のため編集しない（CLAUDE.md）。幸い installKB は
// インスタンスを window._kb として公開しているので、ここでインスタンス側に上書きする。
// 元の 4 分岐のロジックはそのまま踏襲し、閉じ括弧と行番号の下限クランプだけを直す。
// hterm を更新したときは、この上書きが不要になっていないか見直すこと。
function term_mtPatchIME() {
  var kb = window._kb;
  if (!kb || kb.__mtIMEPatched) {
    return;
  }
  kb.__mtIMEPatched = true;

  var OFFSCREEN = '-9999px';

  // (1) 閉じ括弧の欠落を直した _moveCaret。
  kb._moveCaret = function(str) {
    var term = this._t;
    var scrollPort = term.scrollPort_;
    var caret = this.caret;

    caret.style.backgroundColor = lib.colors.setAlpha(term.getCursorColor(), 1);
    caret.style.color = scrollPort.getBackgroundColor();

    var cols = term.screenSize.width;
    var rows = term.screenSize.height;
    var col = term.screen_.cursorPosition.column;
    var row = term.screen_.cursorPosition.row;
    var width = lib.wc.strWidth(str);

    caret.style.bottom = 'auto';
    caret.style.top = 'auto';
    caret.style.left = 'auto';
    caret.style.right = 'auto';

    // 未確定文字が無いときは画面外へ退避する（通常の英数入力中はこの状態）
    if (width === 0) {
      caret.style.top = OFFSCREEN;
      caret.style.left = OFFSCREEN;
      return;
    }

    var rowTop = function(r) {
      // 行番号が負になると画面外上方へ飛ぶので下限でクランプする
      return 'calc(var(--hterm-charsize-height) * ' + Math.max(0, r) + ')';
    };

    if (width >= cols) {
      // 1 行に収まらない: 全幅を使い、カーソルの上下どちらかへ寄せる
      caret.style.left = '0px';
      caret.style.right = '0px';
      caret.style.top = row < 0.8 * rows
        ? rowTop(row + 1)
        : rowTop(row - Math.floor(width / (cols + 1)) - 1);
    } else if (col + width <= cols) {
      // カーソル位置からそのまま収まる: カーソルに重ねる
      caret.style.left = 'calc(var(--hterm-charsize-width) * ' + col + ')';
      caret.style.top = rowTop(row);
      caret.style.right = 'auto';
    } else if (row === 0) {
      // 折り返すが 0 行目なので下の行へ、右寄せ
      caret.style.top = rowTop(row + 1);
      caret.style.left = 'auto';
      caret.style.right = '0px';
    } else {
      // 折り返すので上の行へ、右寄せ（元実装はここで calc( が閉じていなかった）
      caret.style.top = rowTop(row - 1);
      caret.style.left = 'auto';
      caret.style.right = '0px';
    }
  };

  // (2) 確定（および通常の出力）のあと、画面に出たままの caret を退避状態へ戻す。
  //     毎打鍵で呼ばれる経路なので、実際に画面に出ているときだけ戻す。
  var originalOutput = kb._output;
  if (typeof originalOutput === 'function') {
    // 元の _output はインスタンスに束縛されたアロー関数なので receiver は無関係だが、
    // 将来 prototype メソッドに変わっても壊れないよう call で明示する。
    kb._output = function(data) {
      originalOutput.call(kb, data);
      if (kb.caret && kb.caret.style.top !== OFFSCREEN) {
        kb._moveCaret('');
      }
    };
  }
}
function term_setup(accessibilityEnabled) {
  t = new hterm.Terminal('blink');

  t.onTerminalReady = function() {
    window.installKB(t, t.scrollPort_.screen_);
    // 上書きに失敗しても端末の初期化（この下の設定）は必ず続ける
    try { term_mtPatchIME(); } catch (e) { console.error('term_mtPatchIME failed', e); }
    term_setAutoCarriageReturn(true);
    term_setClipboardWrite(false);

    t.setCursorVisible(true);
    t.io.onTerminalResize = function(cols, rows) {
      _postMessage('sigwinch', {cols, rows});
      if (t.prompt) {
        t.prompt.resize();
      }
    };

    var size = {
      cols: t.screenSize.width,
      rows: t.screenSize.height,
    };
    
    document.body.style.backgroundColor =
      t.scrollPort_.screen_.style.backgroundColor;
    var bgColor = _colorComponents(t.scrollPort_.screen_.style.backgroundColor);
    
    t.keyboard.characterEncoding = 'raw'; // we are UTF8. Fix for #507
    t.uninstallKeyboard();
    
    _postMessage('terminalReady', {size, bgColor});

    if (window.KeystrokeVisualizer) {
      window.KeystrokeVisualizer.enable();
    }
    t.setAccessibilityEnabled(accessibilityEnabled);
  };

  t.decorate(document.getElementById('terminal'));
}

function term_init(accessibilityEnabled, lockdownMode) {
  term_setupDefaults();
  try {
    applyUserSettings();
    //    var bgColor = term_get('background-color');
    //    document.body.style.backgroundColor = bgColor;
    //    document.body.parentNode.style.backgroundColor = bgColor;
    if (lockdownMode) {
      term_setup(accessibilityEnabled);
    } else {
      waitForFontFamily(term_setup);
    }
  } catch (e) {
    _postMessage('alert', {
      title: 'Error',
      message:
        'Failed to setup theme. Please check syntax of your theme.\n' +
        e.toString(),
    });
    term_setup(accessibilityEnabled);
  }
}

var _requestId = 0;
var _requestsMap = {};

class ApiRequest {
  constructor(name, request) {
    this.id = _requestId++;
    request.id = this.id;
    var self = this;
    this.promise = new Promise(function(resolve, reject) {
        self.resolve = resolve;
        self.reject = reject;
    });
    _requestsMap[this.id] = self
    _postMessage("api", {name, request: JSON.stringify(request)} );
    
    this.then = this.promise.then.bind(this.promise);
    this.catch = this.promise.catch.bind(this.promise);
  }
  
  cancel() {
    this.resolve(null);
    delete _requestsMap[this.id];
  }
}

function term_apiRequest(name, request) {
  return new ApiRequest(name, request)
}

function term_apiResponse(name, response) {
  var res = JSON.parse(response);
  var req = _requestsMap[res.requestId];
  if (!req) {
    return;
  }
  delete _requestsMap[req.id];
  req.resolve(res)
}


window.term_apiRequest = term_apiRequest;
window.term_apiResponse = term_apiResponse;

function term_write(data) {
  t.interpret(data);
}

function term_paste(str) {
  t.onPaste_({text: str || ''});
}

var _utf8TextDecoder = new TextDecoder('utf8');
function term_write_b64(b64str) {
  var bytes = base64js.toByteArray(b64str); // b64_to_uint8_array(b64str);
  var data = _utf8TextDecoder.decode(bytes);
  t.interpret(data);
};

function b64_to_uint8_array(b64Str) {
  var s = atob(b64Str);
  var len = s.length;
  var res = new Uint8Array(len);
  for (var i = 0; i < len; i++) {
    res[i] = s.charCodeAt(i);
  }
  return res;
}

function term_clear() {
  t.clear();
}

function term_reset() {
  t.reset();
}

function term_focus() {
  t.onFocusChange__(true);
}

function term_blur() {
  t.onFocusChange__(false);
}

function _setTermCoordinates(event, x, y) {
  // One based row/column stored on the mouse event.
  var ty = (y / t.scrollPort_.characterSize.height | 0) + 1;
  var tx = (x / t.scrollPort_.characterSize.width | 0) + 1;
//  console.log(`x:${x},y: ${y}, col:${tx}, row:${ty}`);
  event.terminalRow = ty;
  event.terminalColumn = tx;
}

function term_reportMouseClick(x, y, buttons, display) {
  if (!t.prompt) {
    return;
  }

  var event = new MouseEvent(name, {buttons});
  _setTermCoordinates(event, x, y);
  if (!t.prompt.processMouseClick(event)) {
    term_reportMouseEvent('mousedown', x, y, 1);
    term_reportMouseEvent('mouseup', x, y, 1);
  }
                                  
  if (display) {
     term_displayInput("👆", display);
  }
}

function term_reportMouseEvent(name, x, y, buttons) {
  if (!t.prompt) {
    return;
  }

  var event = new MouseEvent(name, {buttons});
  _setTermCoordinates(event, x, y);
  t.onMouse(event);
}

function term_reportWheelEvent(name, x, y, deltaX, deltaY) {
  if (!t.prompt) {
    return;
  }

  var event = new WheelEvent(name, {clientX: x, clientY: y, deltaX, deltaY});
  t.onMouse_Blink(event);
}

function term_setWidth(cols) {
  t.setWidth(cols);
}

function term_increaseFontSize() {
  var size = t.getFontSize();
  term_setFontSize(size + 1 + 'px');
}

function term_decreaseFontSize() {
  var size = t.getFontSize();
  term_setFontSize(size - 1 + 'px');
}

function term_resetFontSize() {
  term_setFontSize();
}

function term_scale(scale) {
  var minScale = 0.3;
  var maxScale = 3.0;
  scale = Math.max(minScale, Math.min(maxScale, scale));
  var fontSize = t.getFontSize();
  var newFontSize = Math.round(fontSize * scale);
  if (fontSize == newFontSize) {
    return;
  }
  term_setFontSize(newFontSize);
}

function term_setFontSize(size) {
  term_set('font-size', size);
  _postMessage('fontSizeChanged', {size: parseInt(size)});
}

function term_setFontFamily(name, fontSizeDetectionMethod) {
  window.fontSizeDetectionMethod = fontSizeDetectionMethod;
  term_set('font-family', name + ', "DejaVu Sans Mono"');
}

function term_setClipboardWrite(state) {
  if (state === false) {
    t.vt.enableClipboardWrite = false;
  } else {
    t.vt.enableClipboardWrite = true;
  }
}

function term_appendUserCss(css) {
  var style = document.createElement('style');

  style.type = 'text/css';
  style.appendChild(document.createTextNode(css));

  document.head.appendChild(style);
}

function term_loadFontFromCss(url, name) {
  WebFont.load({
    custom: {
      families: [name],
      urls: [url],
    },
    active: function() {
      t.syncFontFamily();
    },
  });
  term_setFontFamily(name);
}

function term_getCurrentSelection() {
  const selection = document.getSelection();
    if (!selection || selection.rangeCount === 0 || selection.type === 'Caret') {
    return {base: '', offset: 0, text: ''};
  }

  const r = selection.getRangeAt(0).getBoundingClientRect();

  const rect = `{{${r.x}, ${r.y}},{${r.width},${r.height}}}`;

  return {
    base: selection.baseNode.textContent,
    offset: selection.baseOffset,
    text: selection.toString() || "",
    rect,
  };
}

function _modifySelectionByLine(direction) {
  var selection = document.getSelection();
  var fNode = selection.focusNode;
  var fOffset = selection.focusOffset;
  var aNode = selection.anchorNode;
  var aOffset = selection.anchorOffset;

  var dy =
    direction === 'left'
      ? -t.scrollPort_.characterSize.height
      : t.scrollPort_.characterSize.height;
  var dx = t.scrollPort_.characterSize.width;
  var range = selection.getRangeAt(0);

  var topLeft = true;
  if (fNode === aNode) {
    topLeft = fOffset < aOffset;
  } else {
    topLeft = range.compareNode(selection.focusNode) !== Range.NODE_AFTER;
  }

  if (topLeft) {
    // top left
    var rect = _filteredRects(range)[0];
    var point = {x: rect.left, y: rect.top + Math.abs(dy) * 0.5};
    var newRange = document.caretRangeFromPoint(point.x, point.y + dy);
    if (!newRange) {
      selection.modify('extend', direction, 'line');
    } else {
      if (newRange.startContainer.textContent.length <= newRange.startOffset) {
        if (
          newRange.startContainer.nodeName === 'X-ROW' &&
          newRange.startOffset === 0
        ) {
          selection.setBaseAndExtent(
            aNode,
            aOffset,
            newRange.startContainer,
            newRange.startOffset,
          );
          selection.modify('extend', 'left', 'character');
        } else {
          selection.setBaseAndExtent(
            aNode,
            aOffset,
            newRange.startContainer,
            Math.max(newRange.startOffset - 1, 0),
          );
        }
      } else {
        selection.setBaseAndExtent(
          aNode,
          aOffset,
          newRange.startContainer,
          newRange.startOffset,
        );
      }
    }
  } else {
    // bottom right
    var rects = _filteredRects(range);
    var rect = rects[rects.length - 1];
    var point = {x: rect.right, y: rect.bottom - Math.abs(dy) * 0.5};
    var newRange = document.caretRangeFromPoint(point.x, point.y + dy);
    if (newRange == null) {
      point.x -= dx * 0.5;
    }
    newRange = document.caretRangeFromPoint(point.x, point.y + dy);
    selection.setBaseAndExtent(
      aNode,
      aOffset,
      newRange.startContainer,
      newRange.startOffset,
    );
  }
}

function _filteredRects(range) {
  var res = [];
  var rects = range.getClientRects();
  for (var i = 0; i < rects.length; i++) {
    var r = rects[i];
    if (r.width > 0) {
      res.push(r);
    }
  }
  return res;
}

function term_modifySelection(direction, granularity) {
  var selection = document.getSelection();
  if (!selection || selection.rangeCount === 0) {
    return;
  }

  var fNode = selection.focusNode;
  var fOffset = selection.focusOffset;
  var aNode = selection.anchorNode;
  var aOffset = selection.anchorOffset;

  if (granularity === 'line') {
    _modifySelectionByLine(direction);
    if (selection.isCollapsed) {
      selection.setBaseAndExtent(fNode, fOffset, aNode, aOffset);
      _modifySelectionByLine(direction);
    }

    return;
  }

  selection.modify('extend', direction, granularity);

  // we collapse selection, so swap direction and rerun modification again
  if (selection.isCollapsed) {
    selection.setBaseAndExtent(fNode, fOffset, aNode, aOffset);
    selection.modify('extend', direction, granularity);
  }
}

function term_modifySideSelection() {
  var selection = document.getSelection();
  if (!selection || selection.rangeCount === 0) {
    return;
  }

  selection.setBaseAndExtent(
    selection.focusNode,
    selection.focusOffset,
    selection.anchorNode,
    selection.anchorOffset,
  );
}

function term_cleanSelection() {
  document.getSelection().removeAllRanges();
}

function waitForFontFamily(callback) {
  const fontFamily = term_get('font-family');
  if (!fontFamily) {
    return callback();
  }

  const families = fontFamily.split(/\s*,\s*/);

  WebFont.load({
    custom: {families},
    active: callback,
    inactive: callback,
  });
}

function term_applySexyTheme(theme) {
  term_set('color-palette-overrides', theme.color);
  term_set('foreground-color', theme.foreground);
  term_set('background-color', theme.background);
}

function term_setAutoCarriageReturn(state) {
  t.setAutoCarriageReturn(state);
}

function term_restore() {
  t.primaryScreen_.textAttributes.reset();
  t.setVTScrollRegion(null, null);
  t.setCursorVisible(true);
}

// ─────────────────────────────────────────────────────────────
// MoshTerm: 画面スナップショット（07 #01 ライフライン・スクラブ）
// ─────────────────────────────────────────────────────────────

/// 表示中の行とカーソル位置を取り出す。属性（色・太字）は落ちたプレーンテキスト。
function term_snapshot() {
  try {
    var top = t.scrollbackRows_.length;
    var rows = t.screenSize.height;
    var text = t.getRowsText(top, top + rows);
    var cursor = t.screen_ && t.screen_.cursorPosition
      ? {row: t.screen_.cursorPosition.row, col: t.screen_.cursorPosition.column}
      : {row: 0, col: 0};
    return {
      cols: t.screenSize.width,
      rows: rows,
      text: text,
      cursor: cursor,
      // vim や tmux の代替画面かどうか（戻したときの意味が変わるので記録する）
      alternate: t.screen_ === t.alternateScreen_,
    };
  } catch (e) {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────
// MoshTerm: コマンドブロック（07 #05）
// シェル統合（OSC 133）が入っている環境でのみ動く。無い場合は何も起きない。
//   133;A … プロンプト開始   133;B … コマンド入力開始
//   133;C … コマンド実行開始  133;D;<exit> … 終了
// ─────────────────────────────────────────────────────────────

var _mtBlock = null;

function mt_onShellMark(arg) {
  var parts = String(arg || "").split(";");
  var kind = parts[0];

  if (kind === "C") {
    // 出力の開始。この行より前がコマンド行
    var start = t.getRowCount();
    var commandLine = "";
    if (start > 0) {
      commandLine = t.getRowText(start - 1) || "";
    }
    _mtBlock = {
      startRow: start,
      startedAt: Date.now(),
      command: commandLine.trim(),
    };
    return;
  }

  if (kind === "D") {
    if (!_mtBlock) { return; }
    var exitCode = parts.length > 1 ? parseInt(parts[1], 10) : 0;
    var endRow = t.getRowCount();
    // 行番号はスクロールバックのトリムでずれるため、ここで本文を確定させる
    var output = "";
    try {
      output = t.getRowsText(_mtBlock.startRow, Math.max(_mtBlock.startRow, endRow));
    } catch (e) {
      output = "";
    }
    _postMessage('mt-block', {
      command: _mtBlock.command,
      output: output,
      exitCode: isNaN(exitCode) ? 0 : exitCode,
      duration: (Date.now() - _mtBlock.startedAt) / 1000.0,
    });
    _mtBlock = null;
    return;
  }

  // A（プロンプト開始）と B（入力開始）は区切りのみ。未完のブロックは捨てる
  if (kind === "A") {
    _mtBlock = null;
  }
}

// MoshTerm: 選択範囲の地色をテーマの accent 系に合わせる（06 §5.4）。
// id 固定の <style> を置き換えるので、テーマを切り替えても重複しない。
function term_setSelectionColor(cssColor) {
  var id = 'mt-selection-style';
  var style = document.getElementById(id);
  if (!style) {
    style = document.createElement('style');
    style.id = id;
    style.type = 'text/css';
    document.head.appendChild(style);
  }
  // hterm のスクリーン（x-screen）内の選択に当てる
  style.textContent =
    'x-screen::selection, x-screen ::selection { background-color: ' + cssColor + ' !important; }';
}
