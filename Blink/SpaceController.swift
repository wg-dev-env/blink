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
@objc protocol CommandsHUDViewDelegate: NSObjectProtocol {
  func currentTerm() -> TermController?
  func spaceController() -> SpaceController?
}


import BlinkConfig
import Combine
import MBProgressHUD
import SwiftUI


// MARK: UIViewController
class SpaceController: UIViewController {
  
  struct UIState: UserActivityCodable {
    var keys: [UUID] = []
    var currentKey: UUID? = nil
    var bgColor: CodableColor? = nil
    
    static var activityType: String { "space.ctrl.ui.state" }
  }

  final private lazy var _viewportsController = UIPageViewController(
    transitionStyle: .scroll,
    navigationOrientation: .horizontal
  )
  
  var sceneRole: UISceneSession.Role = UISceneSession.Role.windowApplication
  
  private var _viewportsKeys = [UUID]()
  private var _currentKey: UUID? = nil
  
  private var _hud: MBProgressHUD? = nil
  
  private var _overlay = UIView()
  private var _spaceControllerAnimating: Bool = false
  /// アニメーション中に要求された切替先（last-wins で完了後に 1 件だけ適用する）
  private var _pendingMoveKey: UUID? = nil
  var stuckKeyCode: KeyCode? = nil
  
  private var _snippetsVC: SnippetsViewController? = nil
  private var _blinkMenu: BlinkMenu? = nil
  private var _bottomTapAreaView = UIView()

  // Snips Input Mode tracking
  private var _isSnipsInputModeActive: Bool = false {
    didSet {
      guard _isSnipsInputModeActive != oldValue else { return }
      _configureCapabilitiesForSnipsInputMode(_isSnipsInputModeActive)
    }
  }

  var isSnipsInputModeActive: Bool {
    _isSnipsInputModeActive
  }

  // Capability flags - independent state that controls what's allowed
  private var canTerminalBecomeFirstResponder: Bool = true {
    didSet {
      guard canTerminalBecomeFirstResponder != oldValue else { return }
      currentTerm()?.shouldBlockFirstResponder = !canTerminalBecomeFirstResponder
    }
  }

  private var canDisplayHUD: Bool = true {
    didSet {
      guard canDisplayHUD != oldValue else { return }
      if !canDisplayHUD {
        _hud?.hide(animated: false)
      }
    }
  }

  private var canSwitchPages: Bool = true {
    didSet {
      guard canSwitchPages != oldValue else { return }
      _setPageViewControllerScrollEnabled(canSwitchPages)
    }
  }

  // Configure capabilities based on input mode
  private func _configureCapabilitiesForSnipsInputMode(_ active: Bool) {
    canTerminalBecomeFirstResponder = !active
    canDisplayHUD = !active
    canSwitchPages = !active
  }

  private func _setPageViewControllerScrollEnabled(_ enabled: Bool) {
    // Find and enable/disable scroll gesture recognizers
    for view in _viewportsController.view.subviews {
      if let scrollView = view as? UIScrollView {
        scrollView.isScrollEnabled = enabled
      }
    }
  }
  
  var safeFrame: CGRect {
    _overlay.frame
  }
  
  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    
    guard let window = view.window
    else {
      return
    }
    
    _snippetsVC?.view.frame = _overlay.frame
    
    if let menu = _blinkMenu {
      let size = _overlay.frame.size;
      let menuSize = menu.layout(for: size)
      
      menu.frame = CGRect(
        x: size.width * 0.5 - menuSize.width * 0.5,
        y: _overlay.frame.size.height - menuSize.height - 20,
        width: menuSize.width,
        height: menuSize.height
      )
      self.view.bringSubviewToFront(menu)
    }
        
    FaceCamManager.update(in: self)
    PipFaceCamManager.update(in: self)
   
    DispatchQueue.main.async {
      self.forEachActive { t in
        if t.viewIsLoaded && t.view?.superview == nil {
          _ = t.removeFromContainer()
        }
      }
    }
    let windowBounds = window.bounds
    let height: CGFloat = 22
    _bottomTapAreaView.frame = CGRect(x: windowBounds.width * 0.5 - 250, y: windowBounds.height - height, width: 250 * 2, height: height)
//    _bottomTapAreaView.backgroundColor = UIColor.red
    self.view.bringSubviewToFront(_bottomTapAreaView);
    
  }
  
  private func forEachActive(block:(TermController) -> ()) {
    for key in _viewportsKeys {
      if let ctrl: TermController = SessionRegistry.shared.sessionFromIndexWith(key: key) {
        block(ctrl)
      }
    }
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    
    #if targetEnvironment(macCatalyst)
    guard let appBundleUrl = Bundle.main.builtInPlugInsURL else {
      return
    }
    
    let helperBundleUrl = appBundleUrl.appendingPathComponent("AppKitBridge.bundle")
    
    guard let bundle = Bundle(url: helperBundleUrl) else {
      return
    }
    
    bundle.load()
    
    guard let object = NSClassFromString("AppBridge") as? NSObjectProtocol else {
      return
    }
    
    let selector = NSSelectorFromString("tuneStyle")
    object.perform(selector)
    #endif
  }
  
  private func setupOverlayConstraints() {
    // Overlay positioning to wrap safe areas and keyboard.
    let keyboardGuide = view.keyboardLayoutGuide
    
    _overlay.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      _overlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      _overlay.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      _overlay.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      _overlay.bottomAnchor.constraint(equalTo: keyboardGuide.topAnchor)
    ])
  }
  
  deinit {
    NotificationCenter.default.removeObserver(self)
    // MoshTerm: 繰り返しタイマーを止める（ウィンドウを閉じても残らないように）
    _mtSnapshotTimer?.invalidate()
    _mtShieldTimer?.invalidate()
  }

  @objc private func _setupAppearance() {
    // MoshTerm: MTTheme 選択中はその外観モードと accent を優先する
    self.view.tintColor = MTThemeStore.shared.selectedTheme?.accent.uiColor ?? .cyan
    if let style = MTThemeStore.shared.overrideInterfaceStyle {
      overrideUserInterfaceStyle = style
      return
    }
    switch BLKDefaults.keyboardStyle() {
    case .light:
      overrideUserInterfaceStyle = .light
    case .dark:
      overrideUserInterfaceStyle = .dark
    default:
      overrideUserInterfaceStyle = .unspecified
    }
  }
  
  public override func viewDidLoad() {
    super.viewDidLoad()
    
    _setupAppearance()
    
    view.isOpaque = true
    
    _viewportsController.view.isOpaque = true
    _viewportsController.dataSource = self
    _viewportsController.delegate = self
    
    
    addChild(_viewportsController)
    
    if let v = _viewportsController.view {
      v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      v.layoutMargins = .zero
      v.frame = view.bounds
      view.addSubview(v)
    }
    
    _viewportsController.didMove(toParent: self)
    
    _overlay.isUserInteractionEnabled = false
    view.addSubview(_overlay)
    
    _registerForNotifications()

    setupOverlayConstraints()

    _setupMTTabBar()

    if _viewportsKeys.isEmpty {
      _newShellAction(animated: false)
    } else if let key = _currentKey {
      let term: TermController = SessionRegistry.shared[key]
      term.delegate = self
      // term.layoutProvider = self
      term.bgColor = view.backgroundColor ?? .black
      _viewportsController.setViewControllers([term], direction: .forward, animated: false)
    }
        
    self.view.addSubview(_bottomTapAreaView)
    
    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleQuickActionsAction))
    doubleTap.numberOfTapsRequired = 2
    doubleTap.numberOfTouchesRequired = 1
    _bottomTapAreaView.addGestureRecognizer(doubleTap)
    
    NotificationCenter.default.addObserver(self, selector: #selector(_geoTrackStateChanged), name: NSNotification.Name.BLGeoTrackStateChange, object: nil)
    
//    view.addSubview(_faceCam)
//    addChild(_faceCam.controller)
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { self.alertSubscriptionGroupViolation() }
  }
  
  func alertSubscriptionGroupViolation() {
    // NOTE: Added just in case, as I have seen in RevCat some users ending up in both groups (bc
    // things can still be selected outside the App).
    let msg = """
You may be in two different subscription groups and hence, you may end up overpaying for Blink.
Please go to your subscriptions and cancel one of them!
"""
    
    if EntitlementsManager.shared.groupsCheckViolation() {
      let ctrl = UIAlertController(title: "Important!", message: msg, preferredStyle: .alert)
      ctrl.addAction(UIAlertAction(title: "Ok", style: .default))
      self.present(ctrl, animated: true)
    }
  }
  
  func showAlert(msg: String) {
    let ctrl = UIAlertController(title: "Error", message: msg, preferredStyle: .alert)
    ctrl.addAction(UIAlertAction(title: "Ok", style: .default))
    self.present(ctrl, animated: true)
  }
  
  func _registerForNotifications() {
    let nc = NotificationCenter.default
    
    nc.addObserver(self,
                   selector: #selector(_didBecomeKeyWindow),
                   name: UIWindow.didBecomeKeyNotification,
                   object: nil)
    
    nc.addObserver(self, selector:#selector(_didBecomeKeyWindow), name: UIApplication.didBecomeActiveNotification, object: nil)
    
    nc.addObserver(self, selector: #selector(_setupAppearance),
                   name: NSNotification.Name(rawValue: BKAppearanceChanged),
                   object: nil)
    
    nc.addObserver(self, selector: #selector(_UISceneDidEnterBackgroundNotification(_:)),
                   name: UIScene.didEnterBackgroundNotification, object: nil)
    
    nc.addObserver(self, selector: #selector(_UISceneWillEnterForegroundNotification(_:)),
                   name: UIScene.willEnterForegroundNotification, object: nil)

  }
                   
  @objc func _UISceneDidEnterBackgroundNotification(_ n: Notification) {
    guard let scene = n.object as? UIWindowScene,
          view.window?.windowScene === scene
    else {
      return
    }
    
    let currentTerm = currentTerm()
    
    forEachActive { ctrl in
      if ctrl.viewIsLoaded && ctrl !== currentTerm {
        _ = ctrl.removeFromContainer()
      }
    }
  }
  
  @objc func _UISceneWillEnterForegroundNotification(_ n: Notification) {
    guard let scene = n.object as? UIWindowScene
    else {
      return
    }
    
    #if targetEnvironment(macCatalyst)
    
    if scene.session.persistentIdentifier.hasPrefix("NSMenuBarScene") {
      KBTracker.shared.input?.reportStateWithSelection()
      return
    }
    
    #endif
    
    if scene.session.role == .windowExternalDisplayNonInteractive,
      let sharedWindow = ShadowWindow.shared,
       sharedWindow === view.window,
       let ctrl = sharedWindow.spaceController.currentTerm() {
      
      ctrl.resumeIfNeeded()
    }
    
    guard view.window?.windowScene === scene
    else {
      return
    }
    
    forEachActive { ctrl in
      if ctrl.viewIsLoaded {
        ctrl.placeToContainer()
      }
    }
   
    currentTerm()?.resumeIfNeeded()
   
    #if targetEnvironment(macCatalyst)
    #else
    if view.window === KBTracker.shared.input?.window {
      KBTracker.shared.input?.reportStateWithSelection()
    }
    #endif
  }
    
  @objc func _didBecomeKeyWindow() {
    guard
      presentedViewController == nil,
      let window = view.window,
      window.isKeyWindow
    else {
      currentDevice?.blur()
      return
    }
    
    _focusOnShell()
  }
  
  /// - Parameter display: true なら生成直後に `setViewControllers` で前面表示する（既定）。
  ///   false のときは `_viewportsKeys` の末尾に足して登録だけ行い、表示は呼び出し側に委ねる。
  ///   「すべて開く」で多数のセッションを一括生成するとき、各生成で `setViewControllers` を
  ///   連打すると UIPageViewController が内部不整合でクラッシュするため、背後で作って
  ///   最後に 1 回だけ表示する用途に使う（セッションの接続は表示されるまで遅延される）。
  func _createTerminal(
    userActivity: NSUserActivity?,
    animated: Bool,
    sessionPayload: TermSessionPayload,
    display: Bool = true,
    completion: ((Bool) -> Void)? = nil)
  {
    let term = TermController(sceneRole: sceneRole, sessionPayload: sessionPayload)
    term.delegate = self
    //term.layoutProvider = self
    term.userActivity = userActivity
    term.bgColor = view.backgroundColor ?? .black

    if !display {
      // 背後生成：順序を保つため末尾に足す（現在位置の隣には割り込ませない）
      _viewportsKeys.insert(term.meta.key, at: _viewportsKeys.count)
    } else if let currentKey = _currentKey,
      let idx = _viewportsKeys.firstIndex(of: currentKey)?.advanced(by: 1) {
      _viewportsKeys.insert(term.meta.key, at: idx)
    } else {
      _viewportsKeys.insert(term.meta.key, at: _viewportsKeys.count)
    }
    
    SessionRegistry.shared.track(session: term)

    // MoshTerm: 接続コマンドから拾った alias をこのセッションに紐付ける
    if let alias = _mtPendingAlias {
      MTHostContext.shared.bind(alias: alias, to: term.meta.key)
      _mtPendingAlias = nil
    }
    // MoshTerm: 割り当てた tmux セッション名を記録する（次の接続の衝突判定に使う）
    if let tmuxName = _mtPendingTmuxName {
      MTTmuxSession.shared.store(tmuxName, for: term.meta.key)
      _mtPendingTmuxName = nil
    }

    guard display else {
      // 背後生成：前面表示はしない。接続は表示時（deviceIsReady）まで遅延される。
      completion?(true)
      return
    }

    _currentKey = term.meta.key

    _viewportsController.setViewControllers([term], direction: .forward, animated: animated) { (didComplete) in
      self._displayHUD()
      self._attachInputToCurrentTerm()
      completion?(didComplete)
    }
  }
  
  func _closeCurrentSpace() {
    currentTerm()?.terminate()
    _removeCurrentSpace()
  }
  
  private func _removeCurrentSpace(attachInput: Bool = true) {
    guard
      let currentKey = _currentKey,
      let idx = _viewportsKeys.firstIndex(of: currentKey)
    else {
      return
    }
    currentTerm()?.delegate = nil
    SessionRegistry.shared.remove(forKey: currentKey)
    MTSessionStateCenter.shared.clear(for: currentKey)
    MTHostContext.shared.clear(for: currentKey)
    MTTmuxSession.shared.clear(for: currentKey)
    MTInputGuard.clear(for: currentKey)
    MTShieldCenter.shared.clear(for: currentKey)
    MTSessionEndCenter.shared.clear(for: currentKey)
    MTScreenHistory.shared.clear(for: currentKey)
    MTCommandBlockStore.shared.clear(for: currentKey)
    _viewportsKeys.remove(at: idx)
    if _viewportsKeys.isEmpty {
      _newShellAction(animated: false)
      return
    }

    let direction: UIPageViewController.NavigationDirection
    let term: TermController
    
    if idx < _viewportsKeys.endIndex {
      direction = .forward
      term = SessionRegistry.shared[_viewportsKeys[idx]]
    } else {
      direction = .reverse
      term = SessionRegistry.shared[_viewportsKeys[idx - 1]]
    }
    term.bgColor = view.backgroundColor ?? .black
    
    self._currentKey = term.meta.key
    
    _spaceControllerAnimating = true
    _viewportsController.setViewControllers([term], direction: direction, animated: true) { (didComplete) in
      self._displayHUD()
      if attachInput {
        self._attachInputToCurrentTerm()
      }
      self._spaceControllerAnimating = false
      self._applyPendingMoveIfNeeded(animated: true)
    }
  }
  
  @objc func _focusOnShell() {
    _attachInputToCurrentTerm()
  }
  
  
  private func _attachInputToCurrentTerm() {
    // Check capability flag instead of mode directly
    guard canTerminalBecomeFirstResponder else {
      return
    }
    currentTerm()?.activateInput()
  }

  // MARK: - シートを閉じたら端末へフォーカスを戻す（MoshTerm：コピペ・入力の復活）
  //
  // MT のシート提示（設定・一覧・接続など）は _mtDismissKeyboardForSheet() で端末の
  // ファーストレスポンダを外すが、閉じたときに戻す口が無かった。そのため端末を 1 回
  // タップするまで長押しの編集メニューや ⌘V が効かなくなっていた（WKWebView 側の
  // 選択ジェスチャが focused を要求するため）。閉じ方 2 系統を両方拾って戻す：
  //  ・スワイプで閉じる → presentationControllerDidDismiss（下の delegate 拡張）
  //  ・プログラム/ボタンで閉じる → dismiss(animated:) の override
  // 連鎖提示（閉じた直後に別シートを出す）時は presentedViewController != nil で見送る。
  override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
    if viewControllerToPresent.presentationController?.delegate == nil {
      viewControllerToPresent.presentationController?.delegate = self
    }
    super.present(viewControllerToPresent, animated: flag, completion: completion)
  }

  override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
    super.dismiss(animated: flag) { [weak self] in
      completion?()
      if self?.presentedViewController == nil {
        self?._refocusCurrentTermSoon()
      }
    }
  }

  /// シート（設定・接続・一覧など）を出す前にキーボードを確実に閉じる。
  /// resignInput だけでは端末のキーボードが残り、シート下部の行がキーボードに隠れて
  /// タップできない（＝「反応しない」）ことがあるため、ビュー階層全体の編集も終了させる。
  private func _mtDismissKeyboardForSheet() {
    // キーボードを持つ実体は SmarterTermInput（KBTracker.shared.input）。resignInput() は
    // ガードで効かないことがあるため、この実体を直接 resign し、ビュー階層の編集も終了させる。
    //
    // iPhone では resign だけでは不十分だった。シート表示中に端末デバイスが準備完了
    // （kbDeviceReady）になると TermController が自動で _becomeFirstResponder() を呼び、
    // せっかくシート内の TextField が取ったフォーカスを奪い返す。結果、ホスト追加画面の
    // Alias などに入力できない（タップ無反応）。Snips 入力モード用の shouldBlockFirstResponder
    // を立て、シートが閉じるまで端末入力のファーストレスポンダ化を禁止する（解除は dismiss 側）。
    currentTerm()?.shouldBlockFirstResponder = true
    currentTerm()?.resignInput()
    _ = KBTracker.shared.input?.resignFirstResponder()
    view.window?.endEditing(true)
  }

  /// タブ切替直後に端末がファーストレスポンダに復帰しない問題への対策（MoshTerm）。
  /// タブ（SwiftUI ボタン）のタップ処理と端末の becomeFirstResponder が競合し、Mosh のように
  /// 復帰が重いセッションでは定着タイミングを逃すことがある（ローカルや画面タップは競合なく成功する）。
  /// 切替直後に加えて、ビューが定着したあと（次のラン・短い遅延）にも現在の端末へフォーカスし直す。
  /// 対象は常に currentTerm なので、途中でタブが変わっても誤って別端末を握ることはない。
  private func _refocusCurrentTermSoon() {
    // シート表示中に立てたブロック（_mtDismissKeyboardForSheet）を解除する。
    // ここで戻さないと直後の _attachInputToCurrentTerm がフォーカスを取れない。
    // この関数はシートが完全に閉じた時（presentedViewController == nil）だけ呼ばれるため、
    // 連鎖提示の途中で誤って解除されることはない。
    currentTerm()?.shouldBlockFirstResponder = false
    _attachInputToCurrentTerm()
    DispatchQueue.main.async { [weak self] in self?._attachInputToCurrentTerm() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      self?._attachInputToCurrentTerm()
    }
  }
  
  var currentDevice: TermDevice? {
    currentTerm()?.termDevice
  }
  
  // MARK: - MoshTerm タブバー（S3）・サイドバー（S9）

  private var _mtTabBar: MTTabBarHost? = nil
  private var _mtTabBarLeading: NSLayoutConstraint? = nil
  /// 接続コマンドから拾った alias（_createTerminal でセッションに紐付ける）
  private var _mtPendingAlias: String? = nil
  /// 新規接続に割り当てた tmux セッション名（_createTerminal でセッションに紐付ける）
  private var _mtPendingTmuxName: String? = nil
  // 第3段（常時オーバーレイの遅延生成）: 以下 4 つの表示専用オーバーレイは
  // 起動時には生成せず、機能が初めて発火した瞬間（カード表示・長押し・スクラブ・終了案内）に
  // 初回だけ生成する。普段使い（未発火）ではビュー階層に足さず、タッチ層を軽く保つ。
  private var _mtRingHost: UIViewController? = nil
  private var _mtRingCancellable: AnyCancellable? = nil
  private var _mtScrubHost: UIViewController? = nil
  private var _mtScrubCancellable: AnyCancellable? = nil
  private var _mtStateCancellable: AnyCancellable? = nil
  private var _mtSnapshotTimer: Timer? = nil
  private var _mtShieldTimer: Timer? = nil
  private var _mtShieldCancellable: AnyCancellable? = nil
  private var _mtShieldEnabledCancellable: AnyCancellable? = nil
  private var _mtRevealTap: UITapGestureRecognizer? = nil
  private var _mtEndCancellable: AnyCancellable? = nil
  private var _mtEndHost: UIViewController? = nil
  // 圏外ドラフトのカード。表示専用（ドラフトがある時だけタッチを受ける）
  private var _mtDraftCancellable: AnyCancellable? = nil
  private var _mtDraftHost: UIViewController? = nil
  private var _mtSidebarHost: UIViewController? = nil
  private var _mtSidebarLeading: NSLayoutConstraint? = nil
  private var _mtSidebarVisible = false

  /// iPad / Mac はサイドバーを使う（06 §7。共通実装）
  private var _mtSupportsSidebar: Bool {
    #if targetEnvironment(macCatalyst)
    return true
    #else
    return UIDevice.current.userInterfaceIdiom == .pad
    #endif
  }

  /// MT の「表示専用オーバーレイ」を安全に追加する共通経路（再発防止 A）。
  ///
  /// ここを通す限り、次の 2 つが構造的に保証される:
  ///  - `isUserInteractionEnabled = false` を既定にする（下のタブバー・端末へタッチを通す）
  ///  - `belowTabBar = true` でタブバー領域（上端 + `MTTabBarHost.height`）に重ねない
  ///    → タブバーの ＋・一覧・設定のタップを塞がない
  ///
  /// 個別に `addSubview` + 制約を手書きすると、どれか 1 つで「false 指定漏れ」や
  /// 「タブバー被り」が起きる（実際に draftHost で発生した）。追加は必ずこの経路に寄せる。
  /// タッチを受けたいオーバーレイは、返り値のビューで必要なときだけ true にする。
  @discardableResult
  private func _mtAddOverlay(_ vc: UIViewController,
                             into container: UIView,
                             belowTabBar: Bool = true,
                             bottom: NSLayoutYAxisAnchor) -> UIView {
    addChild(vc)
    let v: UIView = vc.view
    v.backgroundColor = .clear
    // 既定は非インタラクティブ。タッチを受けたいものだけ呼び出し側で true にする
    v.isUserInteractionEnabled = false
    v.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(v)
    // container が self.view のときはセーフエリア基準、それ以外は container の上端基準
    let top = (container === view) ? view.safeAreaLayoutGuide.topAnchor : container.topAnchor
    NSLayoutConstraint.activate([
      v.topAnchor.constraint(equalTo: top, constant: belowTabBar ? MTTabBarHost.height : 0),
      v.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      v.bottomAnchor.constraint(equalTo: bottom),
    ])
    vc.didMove(toParent: self)
    return v
  }

  private func _setupMTTabBar() {
    // 通常のアプリウィンドウにだけ出す（外部ディスプレイ等には出さない）
    guard sceneRole == .windowApplication else { return }

    let host = MTTabBarHost(
      onSelect: { [weak self] key in self?._moveToShell(key: key) },
      onNew: { [weak self] in self?._mtShowConnectSheet() },
      onList: { [weak self] in self?._mtShowSessionsList() },
      onRename: { [weak self] key in self?._mtRenameSession(key) },
      onClose: { [weak self] key in self?._mtCloseSession(key) },
      onDelete: { [weak self] key in self?._mtDeleteSessionWithConfirm(key) },
      onSettings: { [weak self] in self?._mtShowSettings() },
      onCommandBlocks: { [weak self] in self?._mtShowCommandBlocks() },
      onShieldNow: { [weak self] in self?._mtShieldNow() },
      onSFTP: { [weak self] in self?._mtShowSFTPForCurrent() },
      onDisconnect: { [weak self] in self?._mtDisconnectCurrentWithConfirm() },
      onCommandLibrary: { [weak self] in self?._mtShowCommandLibrary() },
      onShortcuts: { [weak self] in self?._mtShowShortcutsHelp() },
      // サイドバーがある iPad / Mac では歯車をサイドバー側に出すので、タブバーには出さない
      showSettings: !_mtSupportsSidebar,
      // サイドバーがある機種だけ、タブバー左端に開閉ボタンを出す（指だけで左メニューを隠せる）
      onToggleSidebar: _mtSupportsSidebar ? { [weak self] in self?._mtToggleSidebar() } : nil
    )
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    let tabLeading = host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      tabLeading,
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.heightAnchor.constraint(equalToConstant: MTTabBarHost.height),
    ])
    host.didMove(toParent: self)
    _mtTabBar = host
    _mtTabBarLeading = tabLeading
    // 端末ビューの上インセットに加算される（LayoutConstraintManager）。
    // ライフライン直下に数 pt の余白を足し、先頭行が帯の真下にきっちり収まるようにする。
    MTChrome.tabBarTopInset = MTTabBarHost.height + MTTabBarHost.contentTopGap

    if _mtSupportsSidebar {
      _setupMTSidebar(sharing: host.model)
    }

    // 状態バナー・トースト（表示専用、常にタッチを通す）
    let statusHost = UIHostingController(rootView: MTStatusOverlayView())
    _mtAddOverlay(statusHost, into: _overlay, bottom: _overlay.bottomAnchor)

    // 回線状態の監視を開始（圏外・回線切替をセッション状態へ変換）
    MTConnectivityMonitor.shared.startIfNeeded()

    // テーマとターミナル配色の同期ずれを自己修復（新規セッションはここから正しい配色になる）
    MTThemeStore.shared.syncTerminalStyleIfNeeded()

    // 圏外ドラフトのカード（表示専用。カードが出ている時だけタッチを受ける）。
    // 第3段：生成はドラフトが初めて貯まったときに _mtActivateDraftOverlay が行う。
    _mtDraftCancellable = MTDraftStore.shared.$drafts.sink { [weak self] _ in
      self?._mtApplyDraftInteractivity()
    }

    // 危険コマンドの長押しリング。確定中だけ全画面でタッチを受けるモーダル。
    // 第3段：生成は長押し判定が初めて走ったときに _mtActivateRingOverlay が行う。
    _mtRingCancellable = MTDangerGuard.shared.$pending.sink { [weak self] pending in
      self?._mtActivateRingOverlay(pending != nil)
    }

    // スクラブ中の読み取り専用オーバーレイ（07 #01）。スクラブ中だけタッチを受ける。
    // 第3段：生成はスクラブが初めて始まったときに _mtActivateScrubOverlay が行う。
    _mtScrubCancellable = MTScreenHistory.shared.$scrubbing.sink { [weak self] snapshot in
      self?._mtActivateScrubOverlay(snapshot != nil)
    }

    // 画面スナップショットを定期的に撮る（07 #01）
    _mtSnapshotTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
      self?._mtTakeSnapshot(reason: "定期")
    }

    // 接続終了の案内（exit 後に固まって見える問題への対応）。
    // 第3段：生成は初めて exit 案内が出たときに _mtActivateEndOverlay が行う。
    // 案内の有無が変わったときも、タブを切り替えたときも、タッチ可否を再計算する
    _mtEndCancellable = MTSessionEndCenter.shared.$ended.sink { [weak self] _ in
      DispatchQueue.main.async { self?._mtApplyEndView() }
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(_mtRemoteSessionDidEnd(_:)),
      name: .MTRemoteSessionDidEnd, object: nil)

    // 覗き見防止（07 #08、既定OFF）。有効なときだけ、5秒ごとの無操作判定と
    // 「伏せている間のタップで戻す」ジェスチャを動かす。既定では何も足さない（タッチ層を軽くする）。
    _mtShieldCancellable = MTShieldCenter.shared.$shielded.sink { [weak self] _ in
      DispatchQueue.main.async { self?._mtApplyShield() }
    }
    _mtShieldEnabledCancellable = MTShieldCenter.shared.$enabled.sink { [weak self] _ in
      DispatchQueue.main.async { self?._mtApplyShieldActivation() }
    }
    // 回線が切れた・戻った・復元した瞬間も撮る
    _mtStateCancellable = MTSessionStateCenter.shared.$states
      .removeDuplicates { old, new in
        guard let key = MTSessionStateCenter.shared.currentKey else { return true }
        return old[key] == new[key]
      }
      .sink { [weak self] states in
        guard let self, let key = MTSessionStateCenter.shared.currentKey,
              let state = states[key] else { return }
        let reason: String
        switch state {
        case .held: reason = "回線断"
        case .reconnecting: reason = "回線切替"
        case .restored: reason = "復元"
        case .connected: return  // 復帰直後は中身が変わっていないので撮らない
        }
        self._mtTakeSnapshot(reason: reason)
      }
  }

  /// Handoff で渡されたセッションを開く（07 #07）
  func mtOpenHandoff(_ payload: MTHandoff.Payload) {
    _mtPendingAlias = payload.alias
    _newShellAction(command: payload.command, animated: true)
    if let title = payload.title, let key = _currentKey {
      MTSessionsStore.shared.setTitle(title, for: key)
      _mtTabBarUpdate()
    }
  }

  /// 今広告している Handoff の内容（alias|title）。同じなら作り直さない
  private var _mtHandoffSignature: String? = nil

  /// 今のセッションを他の端末へ広告する（07 #07）。
  /// _mtTabBarUpdate はキーボード開閉などでも呼ばれるため、内容が変わらなければ何もしない
  private func _mtUpdateHandoffActivity() {
    guard let key = _currentKey, let alias = MTHostContext.shared.alias(for: key) else {
      if _mtHandoffSignature != nil {
        userActivity?.invalidate()
        userActivity = nil
        _mtHandoffSignature = nil
      }
      return
    }
    let title = MTSessionsStore.shared.title(for: key) ?? alias
    let signature = "\(alias)|\(title)"
    guard signature != _mtHandoffSignature else { return }

    guard let activity = MTHandoff.makeActivity(alias: alias, title: title) else { return }
    userActivity?.invalidate()
    userActivity = activity
    activity.becomeCurrent()
    _mtHandoffSignature = signature
  }

  /// リモート接続が終わった（exit した）ときの案内を出す。
  /// どのセッションが終わったかは通知の sessionKey で判断する（現在タブとは限らない）
  @objc private func _mtRemoteSessionDidEnd(_ note: Notification) {
    let command = (note.userInfo?["command"] as? String) ?? ""
    let keyString = note.userInfo?["sessionKey"] as? String
    DispatchQueue.main.async {
      guard let keyString, let key = UUID(uuidString: keyString) else { return }
      // このウィンドウが持っているセッションのときだけ記録する（複数ウィンドウ対応）
      guard self._viewportsKeys.contains(key) else { return }
      MTSessionEndCenter.shared.note(command: command, for: key)

      // 64_MoshTerm: ローカルシェルに戻ったので、タブ名を接続先 alias から端末名
      // （iPhone 等）へ戻す。再接続コマンドは MTSessionEndCenter が別に保持するため
      // 「もう一度つなぐ」は壊れない。安全機能（額縁等）もローカルでは外れるのが正しい。
      // この通知は本当の exit 時のみ飛ぶ（Mosh detach/resume では飛ばない）ので誤消去しない。
      MTHostContext.shared.clear(for: key)
      // 残っているリモートのタイトルを消し、フォールバックで端末名を表示させる。
      let term: TermController = SessionRegistry.shared[key]
      term.title = nil
      self._mtTabBarUpdate()
    }
  }

  /// 終了案内のタッチ可否を、現在タブに案内が出ているかで決める。
  /// 第3段：案内が初めて出るときにオーバーレイを生成する。
  private func _mtApplyEndView() {
    let show = _currentKey.map { MTSessionEndCenter.shared.ended(for: $0) != nil } ?? false
    _mtActivateEndOverlay(show)
  }

  // MARK: - MoshTerm 第3段：常時オーバーレイの遅延生成
  //
  // 下の 4 つは「初めて必要になった瞬間」に 1 度だけ生成し、以後は保持したまま
  // isHidden / isUserInteractionEnabled の切り替えだけで出し入れする。
  // 起動直後や、機能が一度も発火しないセッションではビュー階層に足さない。

  /// 圏外ドラフトのカード（07 #02）を遅延生成する
  private func _mtActivateDraftOverlay(_ active: Bool) {
    if active && _mtDraftHost == nil {
      let host = UIHostingController(rootView: MTDraftOverlayView(onSend: { [weak self] lines in
        self?._mtSendDraftLines(lines)
      }))
      _mtAddOverlay(host, into: view, bottom: view.keyboardLayoutGuide.topAnchor)
      _mtDraftHost = host
    }
    _mtSetOverlay(_mtDraftHost, active: active)
  }

  /// 危険コマンドの長押しリング（07 #04）を遅延生成する。
  /// belowTabBar=false で全画面を覆うが、生成も表示も pending の間だけ。
  private func _mtActivateRingOverlay(_ active: Bool) {
    if active && _mtRingHost == nil {
      let host = UIHostingController(rootView: MTDangerRingView())
      _mtAddOverlay(host, into: view, belowTabBar: false, bottom: view.bottomAnchor)
      _mtRingHost = host
    }
    _mtSetOverlay(_mtRingHost, active: active)
  }

  /// スクラブ中の読み取り専用オーバーレイ（07 #01）を遅延生成する
  private func _mtActivateScrubOverlay(_ active: Bool) {
    if active && _mtScrubHost == nil {
      let host = UIHostingController(rootView: MTScrubOverlayView())
      _mtAddOverlay(host, into: view, bottom: view.keyboardLayoutGuide.topAnchor)
      _mtScrubHost = host
    }
    _mtSetOverlay(_mtScrubHost, active: active)
  }

  /// 接続終了の案内（exit 後に固まって見える問題への対応）を遅延生成する
  private func _mtActivateEndOverlay(_ active: Bool) {
    if active && _mtEndHost == nil {
      let host = UIHostingController(rootView: MTSessionEndView(
        onReconnect: { [weak self] command in
          self?._newShellAction(command: command, animated: false)
        },
        onNewConnection: { [weak self] in self?._mtShowConnectSheet() },
        onCloseTab: { [weak self] in self?._closeCurrentSpace() }
      ))
      _mtAddOverlay(host, into: view, bottom: view.bottomAnchor)
      _mtEndHost = host
    }
    _mtSetOverlay(_mtEndHost, active: active)
  }

  /// 生成済みオーバーレイの表示・タッチ可否をまとめて切り替える（未生成なら何もしない）
  private func _mtSetOverlay(_ host: UIViewController?, active: Bool) {
    guard let v = host?.view else { return }
    v.isHidden = !active
    v.isUserInteractionEnabled = active
  }

  /// 覗き見防止の有効/無効に応じて、5秒タイマーとルートビューのタップジェスチャを付け外しする。
  /// 既定（無効）ではどちらも存在しないので、ルートビューに常時ジェスチャが乗らず、タッチ層が軽い。
  private func _mtApplyShieldActivation() {
    if MTShieldCenter.shared.enabled {
      if _mtShieldTimer == nil {
        _mtShieldTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
          guard let self else { return }
          MTShieldCenter.shared.checkIdle(currentKey: self._currentKey)
        }
      }
      if _mtRevealTap == nil {
        let tap = UITapGestureRecognizer(target: self, action: #selector(_mtRevealTapped))
        tap.delegate = self
        _mtRevealTap = tap
        view.addGestureRecognizer(tap)
      }
    } else {
      _mtShieldTimer?.invalidate()
      _mtShieldTimer = nil
      if let tap = _mtRevealTap {
        view.removeGestureRecognizer(tap)
        _mtRevealTap = nil
      }
    }
  }

  /// 伏せる・戻すを端末へ反映する（07 #08）
  private func _mtApplyShield() {
    guard let term = currentTerm(), let key = _currentKey else { return }
    let theme = MTThemeStore.shared.currentTheme
    if MTShieldCenter.shared.isShielded(key) {
      let message = MTShieldCenter.shared.requireAuth
        ? "伏せています · タップして Face ID で戻す"
        : "伏せています · タップで戻す"
      term.termView.setMTShield(
        message: message,
        background: theme.bg.uiColor,
        barColor: theme.raised.uiColor,
        textColor: theme.muted.uiColor)
      // 伏せている間は入力を受け付けない（不可視のまま打鍵が端末に届くのを防ぐ）
      KBTracker.shared.input?.reset()
      _ = KBTracker.shared.input?.resignFirstResponder()
    } else {
      term.termView.setMTShield(message: nil, background: nil, barColor: nil, textColor: nil)
      _attachInputToCurrentTerm()
    }
  }

  @objc private func _mtRevealTapped() {
    guard let key = _currentKey, MTShieldCenter.shared.isShielded(key) else { return }
    MTShieldCenter.shared.reveal(key)
  }

  /// 今すぐ伏せる（メニューから）
  private func _mtShieldNow() {
    guard let key = _currentKey else { return }
    MTShieldCenter.shared.shield(key)
  }

  /// 今の画面を撮ってセッションの履歴に積む（07 #01）
  private func _mtTakeSnapshot(reason: String) {
    guard let key = _currentKey, let term = currentTerm() else { return }
    term.termView.mtSnapshot { dict in
      guard let dict = dict as? [String: Any],
            let snapshot = MTScreenSnapshot(dictionary: dict, reason: reason) else { return }
      MTScreenHistory.shared.add(snapshot, for: key)
    }
  }

  /// コマンド履歴（07 #05）をシートで開く
  private func _mtShowCommandBlocks() {
    let vc = UIHostingController(rootView: MTCommandBlocksView(sessionKey: _currentKey))
    vc.overrideUserInterfaceStyle = MTThemeStore.shared.overrideInterfaceStyle ?? .unspecified
    vc.modalPresentationStyle = .pageSheet
    _mtDismissKeyboardForSheet()
    present(vc, animated: true)
  }

  /// コマンドライブラリ（S19）をシートで開く。選択で現在セッションへ改行なし挿入。
  private func _mtShowCommandLibrary() {
    let vc = UIHostingController(rootView: MTCommandLibraryView(onInsert: { [weak self] command in
      self?.currentDevice?.receive(command)
    }))
    vc.overrideUserInterfaceStyle = MTThemeStore.shared.overrideInterfaceStyle ?? .unspecified
    vc.modalPresentationStyle = .pageSheet
    _mtDismissKeyboardForSheet()
    present(vc, animated: true)
  }

  /// キーボードショートカット一覧（チートシート）をシートで開く（⌘/ または「…」メニュー）
  private func _mtShowShortcutsHelp() {
    // 二重提示を避ける（連打・メニューと⌘/の競合対策）
    if presentedViewController is UIHostingController<MTShortcutsView> { return }
    let vc = UIHostingController(rootView: MTShortcutsView())
    vc.overrideUserInterfaceStyle = MTThemeStore.shared.overrideInterfaceStyle ?? .unspecified
    vc.modalPresentationStyle = .pageSheet
    _mtDismissKeyboardForSheet()
    present(vc, animated: true)
  }

  /// ドラフトの行をまとめて送る（復帰後）
  private func _mtSendDraftLines(_ lines: [String]) {
    guard let device = currentDevice else { return }
    for line in lines {
      device.write(line + "\r")
    }
  }

  /// 現在のセッションの接続先に応じて額縁を出す（07 #03）
  private func _mtApplyHostFrame() {
    guard let term = currentTerm() else { return }
    let alias = MTHostContext.shared.alias(for: _currentKey)
    let host = alias.flatMap { BKHosts.withHost($0) }
    let frame = MTSafety.frame(for: host)
    let theme = MTThemeStore.shared.currentTheme

    guard frame.style != .none, frame.style != .auto else {
      term.termView.setMTFrame(color: nil, width: 0, label: nil)
      return
    }

    let env = MTSafety.environment(for: host)
    let color: UIColor = frame.colorHex.flatMap { MTColor(hex: $0)?.uiColor }
      ?? (env == .production ? theme.warn.uiColor : theme.accent.uiColor)
    term.termView.setMTFrame(
      color: color,
      width: frame.style.width,
      label: MTSafety.frameLabel(forAlias: alias))
  }

  /// セッション一覧（06 §6.2）をシートで表示する
  private func _mtShowSessionsList() {
    let items = _viewportsKeys.enumerated().map { index, key -> MTTabItem in
      let number = index + 1
      if let custom = MTSessionsStore.shared.title(for: key) {
        return MTTabItem(key: key, title: custom, index: number)
      }
      if let alias = MTHostContext.shared.alias(for: key) {
        return MTTabItem(key: key, title: alias, index: number)
      }
      let term: TermController = SessionRegistry.shared[key]
      let title = term.title ?? ""
      return MTTabItem(key: key, title: title.isEmpty ? MTDeviceInfo.name : title, index: number)
    }
    let view = MTSessionsView(
      items: items,
      currentKey: _currentKey,
      onSelect: { [weak self] key in
        // onNew / onDelete と同じ理由。行タップは dismiss() 直後に onSelect を呼ぶため、
        // _moveToShell 内の setViewControllers（ページ切替）がシート dismiss と重なって
        // 落ち、「タップしても該当セッションに切り替わらない」症状になる。閉じ終わって
        // から切り替える。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
          self?._moveToShell(key: key)
        }
      },
      onNew: { [weak self] in
        // 一覧シートの dismiss と競合しないよう、閉じ終わってから接続シートを開く
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
          self?._mtShowConnectSheet()
        }
      },
      onDelete: { [weak self] key in
        // onNew と同様、一覧シートの dismiss と競合しないよう閉じ終わってから削除する。
        // 削除は内部で setViewControllers（ページ切替）を呼ぶため、シート dismiss と
        // 重なると操作が落ちて「無反応・タブも消えない」症状になる。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
          self?._mtDeleteSession(key)
        }
      }
    )
    let vc = UIHostingController(rootView: view)
    vc.modalPresentationStyle = .pageSheet
    present(vc, animated: true)
  }

  /// サイドバー（06 §7、幅 264pt、⌘⇧S で開閉）。タブバーとモデルを共有する。
  private func _setupMTSidebar(sharing model: MTTabBarModel) {
    let view = MTSidebarView(
      model: model,
      onSelect: { [weak self] key in self?._moveToShell(key: key) },
      onConnect: { [weak self] alias, kind in
        self?._mtConnect(alias: alias, kind: kind)
      },
      onNewConnection: { [weak self] in self?._mtShowConnectSheet() },
      onRename: { [weak self] key in self?._mtRenameSession(key) },
      onClose: { [weak self] key in self?._mtCloseSession(key) },
      onDelete: { [weak self] key in self?._mtDeleteSessionWithConfirm(key) },
      onSettings: { [weak self] in self?._mtShowSettings() },
      onCommandBlocks: { [weak self] in self?._mtShowCommandBlocks() },
      onShieldNow: { [weak self] in self?._mtShieldNow() },
      onSFTP: { [weak self] in self?._mtShowSFTPForCurrent() },
      onDisconnect: { [weak self] in self?._mtDisconnectCurrentWithConfirm() },
      onCommandLibrary: { [weak self] in self?._mtShowCommandLibrary() },
      onShortcuts: { [weak self] in self?._mtShowShortcutsHelp() }
    )
    let host = UIHostingController(rootView: view)
    host.view.backgroundColor = .clear
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    self.view.addSubview(host.view)
    let leading = host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor)
    NSLayoutConstraint.activate([
      leading,
      host.view.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
      host.view.widthAnchor.constraint(equalToConstant: MTSidebarView.width),
    ])
    host.didMove(toParent: self)
    _mtSidebarHost = host

    // 既定で表示（⌘⇧S で開閉）
    _mtSidebarVisible = true
    _mtSidebarLeading = leading
    leading.constant = 0
    _mtTabBarLeading?.constant = MTSidebarView.width
    MTChrome.sidebarLeftInset = MTSidebarView.width
  }

  private func _mtToggleSidebar() {
    guard let sidebarLeading = _mtSidebarLeading else { return }
    _mtSidebarVisible.toggle()
    let visible = _mtSidebarVisible
    sidebarLeading.constant = visible ? 0 : -MTSidebarView.width
    _mtTabBarLeading?.constant = visible ? MTSidebarView.width : 0
    MTChrome.sidebarLeftInset = visible ? MTSidebarView.width : 0

    UIView.animate(withDuration: 0.25) {
      self.view.layoutIfNeeded()
    }
    // 開いている全端末のインセットを再計算させる
    forEachActive { term in
      term.termView.constraintManager?.update(term.termView.currentLayoutMode())
    }
  }

  /// 設定（06 §6.5）をシートで開く（タブバー・サイドバーの歯車）
  private func _mtShowSettings() {
    let navController = UINavigationController()
    let rootView = NavView(navController: navController) { MTSettingsView() }
    let content = UIHostingController(rootView: rootView)
    content.navigationItem.leftBarButtonItem = UIBarButtonItem(
      systemItem: .close,
      primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    navController.setViewControllers([content], animated: false)
    navController.overrideUserInterfaceStyle = MTThemeStore.shared.overrideInterfaceStyle ?? .unspecified
    navController.modalPresentationStyle = .pageSheet
    _mtDismissKeyboardForSheet()
    present(navController, animated: true)
  }

  /// セッション名の手動変更（タブ長押し →「名前を変更」）。シェルの自動タイトルより優先される。
  private func _mtRenameSession(_ key: UUID) {
    let store = MTSessionsStore.shared
    let term: TermController = SessionRegistry.shared[key]
    let current = store.title(for: key) ?? (term.title ?? "")

    let number = (_viewportsKeys.firstIndex(of: key).map { $0 + 1 }).map { "\($0) 番 · " } ?? ""
    let alert = UIAlertController(
      title: "\(number)名前を変更",
      message: "空にすると、接続先のホスト名（ローカルは shell）に戻ります",
      preferredStyle: .alert)
    alert.addTextField { field in
      field.text = current
      field.placeholder = MTHostContext.shared.alias(for: key) ?? "セッション名"
      field.clearButtonMode = .whileEditing
      field.autocapitalizationType = .none
    }
    alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
    alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
      store.setTitle(alert?.textFields?.first?.text, for: key)
      self?._mtTabBarUpdate()
    })
    present(alert, animated: true)
  }

  /// 任意のセッションを閉じる（タブの「×」・長押しメニュー）
  private func _mtCloseSession(_ key: UUID) {
    if key == _currentKey {
      _closeCurrentSpace()
      return
    }
    let term: TermController = SessionRegistry.shared[key]
    term.delegate = nil
    term.terminate()
    SessionRegistry.shared.remove(forKey: key)
    // _removeCurrentSpace と同じ後始末を揃える（非カレント閉じで取り残しが出ないように）
    MTSessionStateCenter.shared.clear(for: key)
    MTHostContext.shared.clear(for: key)
    MTTmuxSession.shared.clear(for: key)
    MTSessionsStore.shared.setTitle(nil, for: key)
    if let idx = _viewportsKeys.firstIndex(of: key) {
      _viewportsKeys.remove(at: idx)
    }
    _mtTabBarUpdate()
  }

  /// セッションを削除する：サーバーの tmux セッションごと終了してから閉じる（破壊的・S削除機能）。
  ///
  /// 「閉じる／隠す」は iOS 側の接続を切るだけでサーバーの tmux は残す設計のため、
  /// 不要セッションを根こそぎ消したいとき専用。tmux 名とホストを**閉じる前に**捕捉し、
  /// 両方そろっていれば `tmux kill-session` を発行する。tmux を使っていない接続
  /// （ローカルシェル・tmux 無し SSH 等）は kill をスキップして通常の閉じるに落ちる。
  private func _mtDeleteSession(_ key: UUID) {
    // 閉じると対応表がクリアされるため、先に名前とホストを取り出す
    let tmuxName = MTTmuxSession.shared.name(for: key)
    let alias = MTHostContext.shared.alias(for: key)
    _mtCloseSession(key)
    // tmux 名 or ホストが記録されていない接続（手打ち mosh・tmux 無し・ローカル）は
    // kill 対象が不明。以前は無言でスキップしていたが、破壊的操作が黙って no-op に
    // なるのは誤解のもとなので明示する。
    guard let tmuxName, let alias else {
      _mtToast("このタブには tmux の記録がないため、サーバーのセッションは終了しませんでした")
      return
    }
    Task { [weak self] in
      do {
        let gone = try await MTTmuxKiller.kill(alias: alias, sessionName: tmuxName)
        if !gone {
          await MainActor.run {
            self?._mtToast("tmux「\(tmuxName)」を終了できませんでした（サーバーに残っています）")
          }
        }
      } catch {
        await MainActor.run {
          self?._mtToast("tmux 終了に失敗：\(error.localizedDescription)")
        }
      }
    }
  }

  /// タブ長押しの「削除」用。破壊的なので確認してから `_mtDeleteSession` を呼ぶ。
  /// セッション一覧シートの削除アラートと同じ文言・同じ結末に揃える。
  private func _mtDeleteSessionWithConfirm(_ key: UUID) {
    let name = MTSessionsStore.shared.title(for: key)
      ?? MTHostContext.shared.alias(for: key)
      ?? (SessionRegistry.shared[key] as TermController).title
      ?? "このセッション"
    let alert = UIAlertController(
      title: "セッションを削除",
      message: "「\(name)」をサーバーの tmux セッションごと終了します。元に戻せません。",
      preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
    alert.addAction(UIAlertAction(title: "削除", style: .destructive) { [weak self] _ in
      self?._mtDeleteSession(key)
    })
    present(alert, animated: true)
  }

  /// 現在のセッションを非表示にして、見えている別のセッションへ移る（⌘⇧H）
  private func _mtHideCurrentSession() {
    guard let key = _currentKey else { return }
    MTSessionsStore.shared.hide(key)
    if let next = _viewportsKeys.first(where: { $0 != key && !MTSessionsStore.shared.hiddenKeys.contains($0) }) {
      _moveToShell(key: next)
    }
  }

  /// 接続先を選ぶシート（06 §5.1・§6.3）。ホストを選んで Mosh/SSH 接続、
  /// ローカルシェル、新規ホスト登録（既存 HostView）をまとめた入口。
  private func _mtShowConnectSheet() {
    let navController = UINavigationController()
    let rootView = NavView(navController: navController) {
      MTHostsView(
        onConnect: { [weak self] alias, kind in
          self?.dismiss(animated: true) {
            // mosh/ssh はエイリアス 1 語で BKHosts の設定を解決する（S17: 必要なら tmux ピッカーを挟む）
            self?._mtConnect(alias: alias, kind: kind)
          }
        },
        onLocalShell: { [weak self] in
          self?.dismiss(animated: true) {
            self?.newShellAction()
          }
        },
        onClose: { [weak self] in
          self?.dismiss(animated: true)
        },
        onSFTP: { [weak self] alias in
          self?.dismiss(animated: true) {
            self?._mtShowSFTP(alias: alias)
          }
        }
      )
    }
    // NavView は navController を画面に組み込まないため、設定画面と同じく
    // UINavigationController 自体を present する（push・ナビバーが機能する）
    let content = UIHostingController(rootView: rootView)
    navController.setViewControllers([content], animated: false)
    navController.overrideUserInterfaceStyle = MTThemeStore.shared.overrideInterfaceStyle ?? .unspecified
    navController.modalPresentationStyle = .pageSheet
    _mtDismissKeyboardForSheet()
    present(navController, animated: true)
  }

  /// 接続の共通入口（接続シート・サイドバー）。S17: tmux 自動アタッチ ON の mosh ホストで
  /// ピッカー設定が有効なら、先にサーバーの tmux セッションピッカーを出す。それ以外は即接続。
  private func _mtConnect(alias: String, kind: MTConnectKind) {
    let pickerOn = (UserDefaults.standard.object(forKey: "MTTmuxPickerEnabled") as? Bool) ?? true
    let tmuxOn = BKHosts.withHost(alias)?.tmuxAutoAttach?.boolValue == true
    var isMosh = false
    if case .mosh = kind { isMosh = true }
    if pickerOn, isMosh, tmuxOn {
      _mtShowTmuxPicker(alias: alias, kind: kind)
    } else {
      _newShellAction(command: "\(kind.command) \(alias)", animated: true)
    }
  }

  /// tmux セッションピッカー（S17）を出す。選択後に接続する。
  private func _mtShowTmuxPicker(alias: String, kind: MTConnectKind) {
    let view = MTTmuxPickerView(
      alias: alias,
      // ピッカーは選択時に `dismiss(); onAttach()/onNew()` を同じターンで呼ぶため、
      // シートの dismiss アニメーションと接続側の setViewControllers（ページ切替）が
      // 重なって新規タブが前面に出ないことがある（アプリ再起動で復帰）。一覧シート
      // （MTSessionsView の onSelect/onNew/onDelete）と同じく、閉じ終わってから接続する。
      onAttach: { [weak self] names in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
          self?._mtOpenTmuxSessions(alias: alias, kind: kind, names: names)
        }
      },
      onNew: { [weak self] in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
          self?._newShellAction(command: "\(kind.command) \(alias)", animated: true)
        }
      },
      onWillKill: { [weak self] name in
        // kill の【前】に、同名を焼き込んだアタッチ中タブ（Mosh/SSH）を先に畳む。
        // これをしないと、サーバー側 kill を回線断と誤認した Mosh が自動再接続し、
        // 初期コマンド `tmux new -A -s <name>` を再実行して削除直後の同名を作り直す
        // （ゾンビ復活）。再生成の主体をあらかじめ消しておくのがこの修正の核心。
        self?._mtForgetKilledTmux(alias: alias, name: name)
      },
      onKilled: { [weak self] name in
        // 取りこぼし掃除：onWillKill で畳めなかったタブ（名前不一致等）があれば閉じる。
        self?._mtForgetKilledTmux(alias: alias, name: name)
      })
    let content = UIHostingController(rootView: view)
    content.overrideUserInterfaceStyle = MTThemeStore.shared.overrideInterfaceStyle ?? .unspecified
    content.modalPresentationStyle = .pageSheet
    _mtDismissKeyboardForSheet()
    present(content, animated: true)
  }

  /// ピッカーでサーバーの tmux セッションを削除（kill）したとき、その名前に紐づく
  /// 開いているタブも閉じる。
  ///
  /// ゾンビ復活の原因対策：`tmux new -A -s <name>` を焼き込んだタブが生き残っていると、
  /// 回線切り替え・Mosh 復帰・アプリ再起動によるシーン復元で `-A`（無ければ作成）が
  /// 削除したばかりの同名セッションを再生成してしまう。削除と同時に復活元のタブを
  /// 片付けることで、再生成の起点そのものを断つ。
  ///
  /// `_viewportsKeys` を先にコピー（filter）してからループするため、`_mtCloseSession`
  /// が `_viewportsKeys` を縮めても安全。該当タブが無ければ何もしない（サーバー側の
  /// 掃除だけで、ローカルに復活元が無いケース）。
  private func _mtForgetKilledTmux(alias: String, name: String) {
    let sanitized = TmuxAutoAttach.sanitizedSessionName(name)
    let targets = _viewportsKeys.filter { key in
      MTHostContext.shared.alias(for: key) == alias
        && MTTmuxSession.shared.name(for: key) == sanitized
    }
    for key in targets {
      _mtCloseSession(key)
    }
  }

  /// 選択した tmux セッション名ぶんタブを開く。
  ///
  /// 以前は各セッションを即表示（`setViewControllers`）しながらループしていたため、
  /// 「すべて開く」で 15 個ほど一括生成すると UIPageViewController が内部不整合で
  /// クラッシュしていた。対策として、各タブは背後で登録だけ行い（`display: false`）、
  /// 最後に 1 回だけガード付き `_moveToShell` で表示する。各セッションの接続は、
  /// そのタブが表示された時点（`deviceIsReady`）まで遅延されるため、一度に大量の
  /// Mosh/SSH 接続・WKWebView を張らずに済む（メモリ逼迫による kill も避けられる）。
  private func _mtOpenTmuxSessions(alias: String, kind: MTConnectKind, names: [String]) {
    let safe = names.map { TmuxAutoAttach.sanitizedSessionName($0) }
    guard !safe.isEmpty else { return }
    for name in safe {
      _newShellAction(command: "\(kind.command) \(alias) -- tmux new -A -s \(name)",
                      animated: false, display: false)
    }
    // 末尾（最後に生成したタブ）を 1 回だけ前面に出す。_moveToShell は
    // アニメーション中の再入を抑止するため、ここでの単発呼び出しは安全。
    if let lastKey = _viewportsKeys.last {
      _moveToShell(key: lastKey, animated: true)
    }
  }

  /// 現在タブのホストで SFTP を開く（S18: …メニュー／⌘⇧F から）。
  /// alias が無い（ローカルシェル・tmux 無し等）ときは何もしない。
  private func _mtShowSFTPForCurrent() {
    guard let key = _currentKey, let alias = MTHostContext.shared.alias(for: key) else { return }
    _mtShowSFTP(alias: alias)
  }

  /// 現在タブのセッションを、確認ダイアログを出してから切断（＝閉じる）。S18。
  /// タブの「×」やコンテキストメニューの「閉じる」は即閉じのまま（ここだけ確認を付ける）。
  private func _mtDisconnectCurrentWithConfirm() {
    guard let key = _currentKey else { return }
    let name = MTSessionsStore.shared.title(for: key)
      ?? MTHostContext.shared.alias(for: key)
      ?? "この接続"
    let alert = UIAlertController(
      title: "「\(name)」を切断しますか？", message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
    alert.addAction(UIAlertAction(title: "切断", style: .destructive) { [weak self] _ in
      self?._mtCloseSession(key)
    })
    present(alert, animated: true)
  }

  /// SFTP ファイルブラウザ（S16）を presented sheet で開く
  private func _mtShowSFTP(alias: String) {
    let content = UIHostingController(rootView: MTSFTPBrowserView(alias: alias))
    content.overrideUserInterfaceStyle = MTThemeStore.shared.overrideInterfaceStyle ?? .unspecified
    content.modalPresentationStyle = .pageSheet
    _mtDismissKeyboardForSheet()
    present(content, animated: true)
  }

  private func _mtTabBarUpdate() {
    guard _mtTabBar != nil else { return }
    let items = _viewportsKeys.enumerated().map { index, key -> MTTabItem in
      MTSessionStateCenter.shared.track(key)
      let number = index + 1
      // 手動で付けた名前（06 §5.1）があれば自動タイトルより優先
      if let custom = MTSessionsStore.shared.title(for: key) {
        return MTTabItem(key: key, title: custom, index: number)
      }
      // 次点は接続先のホスト名（ローカルシェルは shell）
      if let alias = MTHostContext.shared.alias(for: key) {
        return MTTabItem(key: key, title: alias, index: number)
      }
      let term: TermController = SessionRegistry.shared[key]
      let title = term.title ?? ""
      return MTTabItem(key: key, title: title.isEmpty ? MTDeviceInfo.name : title, index: number)
    }
    MTSessionStateCenter.shared.currentKey = _currentKey
    _mtTabBar?.update(items: items, current: _currentKey)
    _mtApplyHostFrame()
    _mtApplyShield()
    _mtApplyEndView()
    _mtApplyDraftInteractivity()
    _mtUpdateHandoffActivity()
  }

  /// 圏外ドラフトのカードが出ている時だけ、ドラフトのオーバーレイにタッチを通す。
  /// 出ていない間はタブバー・端末へタッチを素通りさせる（タップ無反応の防止）。
  private func _mtApplyDraftInteractivity() {
    let hasDrafts = _currentKey.map { MTDraftStore.shared.count(for: $0) > 0 } ?? false
    _mtActivateDraftOverlay(hasDrafts)
  }

  /// 短いメッセージを数秒だけ出すトースト（HUD のテキスト表示を流用）。
  /// 破壊的操作の失敗など、黙って終わらせたくない通知に使う。
  func _mtToast(_ message: String) {
    let hud = MBProgressHUD.showAdded(to: _overlay, animated: true)
    hud.mode = .text
    hud.label.text = message
    hud.label.numberOfLines = 0
    hud.bezelView.color = .darkGray
    hud.contentColor = .white
    hud.isUserInteractionEnabled = false
    hud.hide(animated: true, afterDelay: 3)
  }

  private func _displayHUD() {
    _mtTabBarUpdate()
    _hud?.hide(animated: false)

    // Check capability flag instead of mode directly
    guard canDisplayHUD else {
      return
    }

    guard let term = currentTerm() else {
      return
    }
    
    if let bgColor = term.view.backgroundColor, bgColor != .clear {
      view.backgroundColor = bgColor
      _viewportsController.view.backgroundColor = bgColor
      view.window?.backgroundColor = bgColor
    }
    
    let hud = MBProgressHUD.showAdded(to: _overlay, animated: _hud == nil)
    
    hud.mode = .customView
    hud.bezelView.color = .darkGray
    hud.contentColor = .white
    hud.isUserInteractionEnabled = false
    hud.alpha = 0.6
    
    let pages = UIPageControl()
    pages.currentPageIndicatorTintColor = .blinkHudDot
    pages.numberOfPages = _viewportsKeys.count
    let pageNum = _viewportsKeys.firstIndex(of: term.meta.key)
    pages.currentPage = pageNum ?? NSNotFound
    
    hud.customView = pages
    
    let title = term.title?.isEmpty == true ? nil : term.title
    
    var sceneTitle = "[\(pageNum == nil ? 1 : pageNum! + 1) of \(_viewportsKeys.count)] \(title ?? "blink")"
    
    if term.termView.rows == 0 && term.termView.cols == 0 {
      hud.label.numberOfLines = 1
      hud.label.text = title ?? "blink"
    } else {
      let geometry = "\(term.termView.cols)×\(term.termView.rows)"
      hud.label.numberOfLines = 2
      hud.label.text = "\(title ?? "blink")\n\(geometry)"
      
      sceneTitle += " | " + geometry
    }
    
    _hud = hud
    hud.hide(animated: true, afterDelay: 1)
    
    view.window?.windowScene?.title = sceneTitle
    self.view.setNeedsLayout()
  }
  
}

// MARK: UIStateRestorable
// MoshTerm: 伏せているときだけタップを拾う（07 #08）
extension SpaceController: UIGestureRecognizerDelegate {
  public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                shouldReceive touch: UITouch) -> Bool {
    guard gestureRecognizer === _mtRevealTap else { return true }
    return MTShieldCenter.shared.isShielded(_currentKey)
  }

  public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    true
  }
}

extension SpaceController: UIStateRestorable {
  func restore(withState state: UIState) {
    _viewportsKeys = state.keys
    _currentKey = state.currentKey
    if let bgColor = UIColor(codableColor: state.bgColor) {
      view.backgroundColor = bgColor
    }
  }
  
  func dumpUIState() -> UIState {
    return UIState(keys: _viewportsKeys,
            currentKey: _currentKey,
            bgColor: CodableColor(uiColor: view.backgroundColor)
    )
  }
  
  @objc static func onDidDiscardSceneSessions(_ sessions: Set<UISceneSession>) {
    let registry = SessionRegistry.shared
    sessions.forEach { session in
      guard
        let uiState = UIState(userActivity: session.stateRestorationActivity)
      else {
        return
      }
      
      uiState.keys.forEach { registry.remove(forKey: $0) }
    }
  }
}

// MARK: UIPageViewControllerDelegate
extension SpaceController: UIPageViewControllerDelegate {
  public func pageViewController(
    _ pageViewController: UIPageViewController,
    didFinishAnimating finished: Bool,
    previousViewControllers: [UIViewController],
    transitionCompleted completed: Bool) {
    guard completed else {
      return
    }

    guard let termController = pageViewController.viewControllers?.first as? TermController
    else {
      return
    }
    termController.resumeIfNeeded()
    _currentKey = termController.meta.key
    _displayHUD()
    _refocusCurrentTermSoon()

  }
}

// MARK: UIPageViewControllerDataSource
extension SpaceController: UIPageViewControllerDataSource {
  private func _controller(controller: UIViewController, advancedBy: Int) -> UIViewController? {
    guard let ctrl = controller as? TermController else {
      return nil
    }
    let key = ctrl.meta.key
    guard
      let idx = _viewportsKeys.firstIndex(of: key)?.advanced(by: advancedBy),
      _viewportsKeys.indices.contains(idx)
    else {
      return nil
    }
    
    let newKey = _viewportsKeys[idx]
    let newCtrl: TermController = SessionRegistry.shared[newKey]
    newCtrl.delegate = self
    //newCtrl.layoutProvider = self
    newCtrl.bgColor = view.backgroundColor ?? .black
    return newCtrl
  }
  
  public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
    _controller(controller: viewController, advancedBy: -1)
  }

  public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
    _controller(controller: viewController, advancedBy: 1)
  }
  
}

// MARK: TermControlDelegate
extension SpaceController: TermControlDelegate {
  
  func terminalHangup(control: TermController) {
    if currentTerm() == control {
      _closeCurrentSpace()
    }
  }
  
  func terminalDidResize(control: TermController) {
    if currentTerm() == control {
      _displayHUD()
    }
  }
}

// MARK: General tunning

extension SpaceController {
  public override var prefersStatusBarHidden: Bool { true }
  public override var prefersHomeIndicatorAutoHidden: Bool { true }
}


// MARK: Commands

extension SpaceController {
  
  var foregroundActive: Bool {
    view.window?.windowScene?.activationState == UIScene.ActivationState.foregroundActive
  }
  
  public override var keyCommands: [UIKeyCommand]? {
    guard
      let input = KBTracker.shared.input,
      foregroundActive
    else {
      return nil
    }
    
    if let keyCode = stuckKeyCode {
      return [UIKeyCommand(input: "", modifierFlags: keyCode.modifierFlags, action: #selector(onStuckOpCommand))]
    }
    
    return input.blinkKeyCommands
  }
  
  @objc func onStuckOpCommand() {
    stuckKeyCode = nil
    presentedViewController?.dismiss(animated: true)
    _focusOnShell()
  }
  
  @objc func _onBlinkCommand(_ cmd: BlinkCommand) {
    guard foregroundActive,
          let input = currentDevice?.view?.browserView ?? currentDevice?.view?.webView else {
      return
    }
    
//    input.reportStateReset()
    switch cmd.bindingAction {
    case .hex(let hex, stringInput: _, comment: _):
      input.reportHex(hex)
    case .press(let keyCode, mods: let mods):
      input.reportPress(UIKeyModifierFlags(rawValue: mods), keyId: keyCode.id)
    case .command(let c):
      _onCommand(c)
    default:
      break;
    }
  }
  
  @objc func _onShortcut(_ event: UICommand) {
    guard
      let propertyList = event.propertyList as? [String:String],
      let cmd = Command(rawValue: propertyList["Command"]!)
    else {
      return
    }
    _onCommand(cmd)
  }
  
  func _onCommand(_ cmd: Command) {
    guard foregroundActive else {
      return
    }

    switch cmd {
    case .configShow: showConfigAction()
    case .snippetsShow: showSnippetsAction()
    case .scratchShow: showScratchAction()
    case .toggleQuickActions: toggleQuickActionsAction()
    case .toggleGeoTrack: toggleGeoTrack()
    case .tab1: _moveToShell(idx: 0)
    case .tab2: _moveToShell(idx: 1)
    case .tab3: _moveToShell(idx: 2)
    case .tab4: _moveToShell(idx: 3)
    case .tab5: _moveToShell(idx: 4)
    case .tab6: _moveToShell(idx: 5)
    case .tab7: _moveToShell(idx: 6)
    case .tab8: _moveToShell(idx: 7)
    case .tab9: _moveToShell(idx: 8)
    case .tab10: _moveToShell(idx: 9)
    case .tab11: _moveToShell(idx: 10)
    case .tab12: _moveToShell(idx: 11)
    case .tabClose: _closeCurrentSpace()
    case .tabMoveToOtherWindow: _moveToOtherWindowAction()
    case .toggleKeyCast: _toggleKeyCast()
    case .tabNew: _newShellAction()
    case .tabNext: _advanceShell(by: 1)
    case .tabPrev: _advanceShell(by: -1)
    case .tabNextCycling: _advanceShellCycling(by: 1)
    case .tabPrevCycling: _advanceShellCycling(by: -1)
    case .tabLast: _moveToLastShell()
    case .windowClose: _closeWindowAction()
    case .windowFocusOther: _focusOtherWindowAction()
    case .windowNew: _newWindowAction()
    case .clipboardCopy: KBTracker.shared.input?.copy(self)
    case .clipboardCopyRaw: KBTracker.shared.input?.copyRaw(self)
    case .clipboardPaste: KBTracker.shared.input?.paste(self)
    case .selectionGoogle: KBTracker.shared.input?.googleSelection(self)
    case .selectionStackOverflow: KBTracker.shared.input?.soSelection(self)
    case .selectionShare: KBTracker.shared.input?.shareSelection(self)
    case .zoomIn: currentTerm()?.termView.increaseFontSize()
    case .zoomOut: currentTerm()?.termView.decreaseFontSize()
    case .zoomReset: currentTerm()?.termView.resetFontSize()
    case .hideKeyboard: KBTracker.shared.input?.resignFirstResponder()
    case .sidebarToggle: _mtToggleSidebar()
    case .sessionHide: _mtHideCurrentSession()
    // MoshTerm（MT 移植のショートカット）
    case .connectSheetShow: _mtShowConnectSheet()
    case .tmuxPickerShow:
      // 現タブのホストへ tmux ピッカーを開く。alias 不明なら接続シートにフォールバック
      if let key = _currentKey, let alias = MTHostContext.shared.alias(for: key) {
        _mtShowTmuxPicker(alias: alias, kind: .mosh)
      } else {
        _mtShowConnectSheet()
      }
    case .sftpShow:
      if let key = _currentKey, let alias = MTHostContext.shared.alias(for: key) {
        _mtShowSFTP(alias: alias)
      }
    case .commandBlocksShow: _mtShowCommandBlocks()
    case .disconnectCurrent: _mtDisconnectCurrentWithConfirm()
    case .shieldNow: _mtShieldNow()
    case .paletteCycle: MTThemeStore.shared.cycleTerminalPalette()
    case .commandLibraryShow: _mtShowCommandLibrary()
    case .shortcutsHelpShow: _mtShowShortcutsHelp()
    }
  }

  @objc func focusOnShellAction() {
    KBTracker.shared.input?.reset()
    _focusOnShell()
  }
  
  @objc public func scaleWithPich(_ pinch: UIPinchGestureRecognizer) {
    currentTerm()?.scaleWithPich(pinch)
  }
  
  private func _newShellAction(command: String = "", animated: Bool = true, display: Bool = true) {
    let params = MCPParams()
    if !command.isEmpty {
      // MoshTerm: 接続先ホストをセッションに紐付ける（額縁・安全機能が参照、07 #02/#03/#04）
      let alias = MTHostContext.parseAlias(fromCommand: command)
      _mtPendingAlias = alias
      // MoshTerm: 複数接続は別セッションにする（要件4）。bare な mosh 接続で tmux 自動
      // アタッチが有効なら、同じホストの生存セッションと衝突しないユニークな tmux 名を
      // 埋め込む。既に `--`（明示コマンド）があるものや再接続/Handoff の復元コマンドは触らない。
      params.initialCommand = _mtAugmentWithUniqueTmux(command: command, alias: alias)
    }
    let payload = MCPSessionPayload(params: params)
    _createTerminal(userActivity: nil, animated: animated, sessionPayload: payload, display: display)
  }

  /// bare な `mosh <alias>` を、ユニークな tmux セッション名つきコマンドに変換する。
  /// 対象外（ローカル・SSH・既に `--` 付き・tmux 自動アタッチ無効）はそのまま返す。
  /// 割り当てた名前は `_mtPendingTmuxName` に控え、`_createTerminal` でセッションに記録する。
  private func _mtAugmentWithUniqueTmux(command: String, alias: String?) -> String {
    _mtPendingTmuxName = nil
    let words = command.split(separator: " ").map(String.init)
    // S17: ピッカーで `-- tmux new -A -s <name>` が既に焼き込まれている場合は、その名前を
    // 記録してそのまま通す（複数接続や再接続との整合のため MTTmuxSession に残す）。
    if words.contains("--"), let sIdx = words.firstIndex(of: "-s"), sIdx + 1 < words.count {
      _mtPendingTmuxName = words[sIdx + 1]
      return command
    }
    guard
      let alias,
      words.first == "mosh",          // mosh のみ（SSH は ssh_config 側で別対応）
      !words.contains("--"),          // 既に明示コマンドがあるものは触らない
      let host = BKHosts.withHost(alias),
      host.tmuxAutoAttach?.boolValue == true
    else {
      return command
    }
    let base = TmuxAutoAttach.sanitizedSessionName(host.tmuxSessionName)
    let name = MTTmuxSession.shared.assignName(forAlias: alias, base: base)
    _mtPendingTmuxName = name
    return "\(command) -- tmux new -A -s \(name)"
  }

  @objc func newShellAction() {
    _newShellAction()
  }

  @objc func closeShellAction() {
    _closeCurrentSpace()
  }

  private func _focusOtherWindowAction() {
    
    var sessions = _activeSessions()
    
    guard
      sessions.count > 1,
      let session = view.window?.windowScene?.session,
      let idx = sessions.firstIndex(of: session)?.advanced(by: 1)
    else  {
      if currentTerm()?.termView.isFocused() == true {
        currentTerm()?.resignInput()
      } else {
        _focusOnShell()
      }
      return
    }

    if
      let shadowWindow = ShadowWindow.shared,
      let shadowScene = shadowWindow.windowScene,
      let window = self.view.window,
      shadowScene == window.windowScene,
      shadowWindow !== window {
      shadowWindow.makeKeyAndVisible()
      shadowWindow.spaceController._focusOnShell()
      return
    }
          
    sessions = sessions.filter { $0.role != .windowExternalDisplayNonInteractive }
    
    let nextSession: UISceneSession
    if idx < sessions.endIndex {
      nextSession = sessions[idx]
    } else {
      nextSession = sessions[0]
    }
    
    if
      let scene = nextSession.scene as? UIWindowScene,
      let delegate = scene.delegate as? SceneDelegate,
      let window = delegate.window,
      let spaceCtrl = window.rootViewController as? SpaceController {

      if window.isKeyWindow {
        spaceCtrl._focusOnShell()
      } else {
        window.makeKeyAndVisible()
      }
    } else {
      UIApplication.shared.requestSceneSessionActivation(nextSession, userActivity: nil, options: nil, errorHandler: nil)
    }
  }
  
  private func _moveToOtherWindowAction() {
    var sessions = _activeSessions()
    
    guard
      sessions.count > 1,
      let session = view.window?.windowScene?.session,
      let idx = sessions.firstIndex(of: session)?.advanced(by: 1),
      let term = currentTerm(),
      _spaceControllerAnimating == false
    else  {
        return
    }
    
    if
      let shadowWindow = ShadowWindow.shared,
      let shadowScene = shadowWindow.windowScene,
      let window = self.view.window,
      shadowScene == window.windowScene,
      shadowWindow !== window {

      term.prepareForWindowMove()
      _removeCurrentSpace(attachInput: false)
      shadowWindow.makeKey()
      shadowWindow.spaceController._addTerm(term: term)
      return
    }
          
    sessions = sessions.filter { $0.role != .windowExternalDisplayNonInteractive }
    
    let nextSession: UISceneSession
    if idx < sessions.endIndex {
      nextSession = sessions[idx]
    } else {
      nextSession = sessions[0]
    }
    
    guard
      let nextScene = nextSession.scene as? UIWindowScene,
      let delegate = nextScene.delegate as? SceneDelegate,
      let nextWindow = delegate.window,
      let nextSpaceCtrl = nextWindow.rootViewController as? SpaceController,
      nextSpaceCtrl._spaceControllerAnimating == false
    else {
      return
    }


    term.prepareForWindowMove()
    _removeCurrentSpace(attachInput: false)
    nextSpaceCtrl._addTerm(term: term)
    nextWindow.makeKey()
  }
  
  func _toggleKeyCast() {
    BLKDefaults.setKeycasts(!BLKDefaults.isKeyCastsOn())
    BLKDefaults.save()
  }
  
  func _activeSessions() -> [UISceneSession] {
    Array(UIApplication.shared.openSessions)
      .filter({ $0.scene?.activationState == .foregroundActive || $0.scene?.activationState == .foregroundInactive })
      .sorted(by: { $0.persistentIdentifier < $1.persistentIdentifier })
  }
  
  @objc func _newWindowAction() {
    let options = UIWindowScene.ActivationRequestOptions()
    options.requestingScene = self.view.window?.windowScene
    
    UIApplication
      .shared
      .requestSceneSessionActivation(nil,
                                     userActivity: nil,
                                     options: options,
                                     errorHandler: nil)
  }
  
  @objc func _closeWindowAction() {
    guard
      let session = view.window?.windowScene?.session,
      session.role == .windowApplication // Can't close windows on external monitor
    else {
      return
    }
    
    // try to focus on other session before closing
    _focusOtherWindowAction()
    
    UIApplication
      .shared
      .requestSceneSessionDestruction(session,
                                      options: nil,
                                      errorHandler: nil)
  }
  
  @objc func showConfigAction() {
    if let shadowWindow = ShadowWindow.shared,
      view.window == shadowWindow {
      
      _ = currentDevice?.view?.webView.resignFirstResponder()
      
      let spCtrl = shadowWindow.windowScene?.windows.first?.rootViewController as? SpaceController
      spCtrl?.showConfigAction()
      
      return
    }

    DispatchQueue.main.async {
      self.currentTerm()?.resignInput()
      let navCtrl = UINavigationController()
      navCtrl.navigationBar.prefersLargeTitles = true
      let s = SettingsHostingController.createSettings(nav: navCtrl, onDismiss: {
        [weak self] in self?.focusOnShellAction()
      })
      navCtrl.setViewControllers([s], animated: false)
      self.present(navCtrl, animated: true, completion: nil)
    }
  }
  
//  @objc func showWalkthroughAction() {
//    if self.view.window == ShadowWindow.shared {
//      return
//    }
//    DispatchQueue.main.async {
//      _ = KBTracker.shared.input?.resignFirstResponder()
//      let ctrl = UIHostingController(rootView: WalkthroughView(urlHandler: blink_openurl,
//                                                               dismissHandler: { self.dismiss(animated: true) })
//      )
//      ctrl.modalPresentationStyle = .formSheet
//      self.present(ctrl, animated: false)
//    }
//  }
  
  @objc func showSnippetsAction() {
    if let _ = _snippetsVC {
      return
    }
    self.presentSnippetsController()
    if let _ = self._interactiveSpaceController()._blinkMenu {
      self.toggleQuickActionsAction()
    }
  }

  @objc func showScratchAction() {
    if let _ = _snippetsVC {
      return
    }
    self.presentSnippetsControllerWithScratch()
    // if let _ = self._interactiveSpaceController()._blinkMenu {
    //   self.toggleQuickActionsAction()
    // }
  }

  private func _toggleQuickActionActionWith(receiver: SpaceController) {
    if let menu = _blinkMenu {
      _blinkMenu = nil
      UIView.animate(withDuration: 0.15) {
        menu.alpha = 0
      } completion: { _ in
        menu.removeFromSuperview()
      }
    } else {
      let menu = BlinkMenu()
      self.view.addSubview(menu.tapToCloseView)
      
      var ids: [BlinkActionID] = []
      ids.append(contentsOf:  [.snippets, .tabClose, .tabCreate])
      
      if DeviceInfo.shared().hasCorners {
        ids.append(contentsOf:  [.layoutMenu])
      }
      ids.append(contentsOf:  [.toggleLayoutLock, .toggleGeoTrack])
      menu.delegate = receiver;
      menu.build(withIDs: ids, andAppearance: [:])
      _blinkMenu = menu
      self.view.addSubview(menu)
      let size = self.view.frame.size;
      let menuSize = menu.layout(for: size)
      
      let finalMenuFrame = CGRect(x: size.width * 0.5 - menuSize.width * 0.5, y: _overlay.frame.maxY - menuSize.height - 20, width: menuSize.width, height: menuSize.height)
      
      menu.frame = CGRect(origin: CGPoint(x: finalMenuFrame.minX, y: _overlay.frame.maxY + 10), size: finalMenuFrame.size);
      
      UIView.animate(withDuration: 0.25) {
        menu.frame = finalMenuFrame
      }
    }
  }
  
  func _interactiveSpaceController() -> SpaceController {
    if let shadowWin = ShadowWindow.shared,
       self.view.window == shadowWin,
       let mainScreenSession = _activeSessions()
          .first(where: {$0.role == .windowApplication }),
       let delegate = mainScreenSession.scene?.delegate as? SceneDelegate
    {
      return delegate.spaceController
    }
    return self
  }
  
  @objc func toggleQuickActionsAction() {
    _interactiveSpaceController()
      ._toggleQuickActionActionWith(receiver: self)
  }
  
  @objc func toggleGeoTrack() {
    if GeoManager.shared().traking {
      GeoManager.shared().stop()
      return
    }

    let manager = CLLocationManager()
    let status = manager.authorizationStatus
    
    switch status  {
    case .authorizedAlways, .authorizedWhenInUse: break
    case .restricted:
      showAlert(msg: "Geo services are restricted on this device.")
      return
    case .denied:
      showAlert(msg: "Please allow Blink.app to use geo in Settings.app.")
      return
    case .notDetermined:
      GeoManager.shared().authorize()
      return
    @unknown default:
      return
    }
    
    GeoManager.shared().start()
  }
  
  @objc func _geoTrackStateChanged() {
    self.view.setNeedsLayout()
  }
  
  @objc func showWhatsNewAction() {
    if let shadowWindow = ShadowWindow.shared,
      view.window == shadowWindow {

      _ = currentDevice?.view?.webView.resignFirstResponder()

      let spCtrl = shadowWindow.windowScene?.windows.first?.rootViewController as? SpaceController
      spCtrl?.showWhatsNewAction()

      return
    }

    DispatchQueue.main.async {
      self.currentTerm()?.resignInput()
      WhatsNewInfo.setNewVersion()

      let urlString = XCConfig.infoPlistWhatsNewGithubURL()

      if let url = URL(string: urlString) {
        let redirectURL = url.customerTierURL()
        var request = URLRequest(url: redirectURL)
        request.httpMethod = "HEAD"

        URLSession.shared.dataTask(with: request) { _, response, error in
          if error == nil,
             let httpResponse = response as? HTTPURLResponse,
             httpResponse.statusCode == 302,
             let finalURL = response?.url {
            blink_openurl(finalURL)
          } else {
            // Fallback if we cannot get the current announcement
            blink_openurl(URL(string: "https://github.com/blinksh/blink/discussions/categories/announcements")!)
          }
        }.resume()
      }
    }
  }
  
  private func _addTerm(term: TermController, animated: Bool = true) {
    SessionRegistry.shared.track(session: term)
    term.delegate = self
    _viewportsKeys.append(term.meta.key)
    _moveToShell(key: term.meta.key, animated: animated)
  }
  
  private func _moveToShell(idx: Int, animated: Bool = true) {
    guard _viewportsKeys.indices.contains(idx) else {
      return
    }

    let key = _viewportsKeys[idx]
    
    _moveToShell(key: key, animated: animated)
  }
  
  private func _moveToLastShell(animated: Bool = true) {
    _moveToShell(idx: _viewportsKeys.count - 1)
  }
  
  @objc func moveToShell(key: String?) {
    guard
      let key = key,
      let uuidKey = UUID(uuidString: key)
    else {
      return
    }
    _moveToShell(key: uuidKey, animated: true)
  }
  
  private func _moveToShell(key: UUID, animated: Bool = true) {
    // アニメーション中の再入を抑止する。UIPageViewController(.scroll) は
    // setViewControllers(animated:) の完了前に再度呼ぶと内部（_UIQueuingScrollView）が
    // 不整合を起こしてクラッシュする。連打・スワイプ中のタップは「最後の指定」だけを
    // 完了後に 1 件適用する（last-wins）。
    if _spaceControllerAnimating {
      _pendingMoveKey = key
      return
    }

    guard
      let currentKey = _currentKey,
      let currentIdx = _viewportsKeys.firstIndex(of: currentKey),
      let idx = _viewportsKeys.firstIndex(of: key)
    else {
      return
    }

    let term: TermController = SessionRegistry.shared[key]
    let direction: UIPageViewController.NavigationDirection = currentIdx < idx ? .forward : .reverse

    _spaceControllerAnimating = true
    _viewportsController.setViewControllers([term], direction: direction, animated: animated) { (didComplete) in
      term.resumeIfNeeded()
      self._currentKey = term.meta.key
      self._displayHUD()
      self._refocusCurrentTermSoon()
      self._spaceControllerAnimating = false
      self._applyPendingMoveIfNeeded(animated: animated)
    }
  }

  /// アニメーション完了後、保留していた切替先があれば 1 件だけ適用する。
  /// 既に目的のセッションにいる場合（pending == 現在）は何もしない。
  private func _applyPendingMoveIfNeeded(animated: Bool) {
    guard let pending = _pendingMoveKey else { return }
    _pendingMoveKey = nil
    guard pending != _currentKey else { return }
    _moveToShell(key: pending, animated: animated)
  }
  
  private func _advanceShell(by: Int, animated: Bool = true) {
    guard
      let currentKey = _currentKey,
      let idx = _viewportsKeys.firstIndex(of: currentKey)?.advanced(by: by)
    else {
      return
    }
        
    _moveToShell(idx: idx, animated: animated)
  }
  
  private func _advanceShellCycling(by: Int, animated: Bool = true) {
    guard
      let currentKey = _currentKey,
      _viewportsKeys.count > 1
    else {
      return
    }
    
    if let idx = _viewportsKeys.firstIndex(of: currentKey)?.advanced(by: by),
      idx >= 0 && idx < _viewportsKeys.count {
      _moveToShell(idx: idx, animated: animated)
      return
    }
    
    _moveToShell(idx: by > 0 ? 0 : _viewportsKeys.count - 1, animated: animated)
  }
  
}

// MARK: CommandsHUDDelegate
extension SpaceController: CommandsHUDDelegate {
  @objc func currentTerm() -> TermController? {
    if let currentKey = _currentKey {
      return SessionRegistry.shared[currentKey]
    }
    return nil
  }
  
  @objc func spaceController() -> SpaceController? { self }
}

// MARK: SnippetContext

extension SpaceController: SnippetContext {
  
  func _presentSnippetsController(receiver: SpaceController, openScratch: Bool = false) {
    do {
      self.view.window?.makeKeyAndVisible()
      let ctrl = try SnippetsViewController.create(context: receiver, transitionFrame: _blinkMenu?.bounds)
      ctrl.pendingOpenScratch = openScratch
      DispatchQueue.main.async {
        ctrl.view.frame = self.view.bounds
        ctrl.willMove(toParent: self)
        self.view.addSubview(ctrl.view)
        self.addChild(ctrl)
        ctrl.didMove(toParent: self)
        self._snippetsVC = ctrl
        self._isSnipsInputModeActive = true
      }
    } catch {
      self.showAlert(msg: "Could not display Snips: \(error)")
    }
  }

  func presentSnippetsController() {
    _interactiveSpaceController()._presentSnippetsController(receiver: self)
  }

  func presentSnippetsControllerWithScratch() {
    _interactiveSpaceController()._presentSnippetsController(receiver: self, openScratch: true)
  }
  
  func _dismissSnippetsController(ctrl: SpaceController) {
    ctrl.presentedViewController?.dismiss(animated: true)
    ctrl._snippetsVC?.willMove(toParent: nil)
    ctrl._snippetsVC?.view.removeFromSuperview()
    ctrl._snippetsVC?.removeFromParent()
    ctrl._snippetsVC?.didMove(toParent: nil)
    ctrl._snippetsVC = nil
    ctrl._isSnipsInputModeActive = false
  }
  
  func dismissSnippetsController() {
    _dismissSnippetsController(ctrl: _interactiveSpaceController())
    self.focusOnShellAction()
  }
  
  func providerSnippetReceiver() -> (any SnippetReceiver)? {
    self.focusOnShellAction()
    return self.currentDevice
  }

}

// MARK: SceneIntent handlers
extension SpaceController {
  @objc func runShellSessionIntent(command: String = "") {
    DispatchQueue.main.sync {
      self._newShellAction(command: command)
    }
  }

}

// MARK: - シートのスワイプ下げ（ユーザー操作での dismiss）後の再フォーカス（MoshTerm）
extension SpaceController: UIAdaptivePresentationControllerDelegate {
  public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    // 連鎖提示していない時だけ端末へ戻す
    if presentedViewController == nil {
      _refocusCurrentTermSoon()
    }
  }
}
