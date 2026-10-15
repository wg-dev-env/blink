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
  
  func _createTerminal(
    userActivity: NSUserActivity?,
    animated: Bool,
    sessionPayload: TermSessionPayload,
    completion: ((Bool) -> Void)? = nil)
  {
    let term = TermController(sceneRole: sceneRole, sessionPayload: sessionPayload)
    term.delegate = self
    //term.layoutProvider = self
    term.userActivity = userActivity
    term.bgColor = view.backgroundColor ?? .black
    
    if let currentKey = _currentKey,
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
  
  var currentDevice: TermDevice? {
    currentTerm()?.termDevice
  }
  
  // MARK: - MoshTerm タブバー（S3）・サイドバー（S9）

  private var _mtTabBar: MTTabBarHost? = nil
  private var _mtTabBarLeading: NSLayoutConstraint? = nil
  /// 接続コマンドから拾った alias（_createTerminal でセッションに紐付ける）
  private var _mtPendingAlias: String? = nil
  private var _mtRingHost: UIViewController? = nil
  private var _mtRingCancellable: AnyCancellable? = nil
  private var _mtScrubCancellable: AnyCancellable? = nil
  private var _mtStateCancellable: AnyCancellable? = nil
  private var _mtSnapshotTimer: Timer? = nil
  private var _mtShieldTimer: Timer? = nil
  private var _mtShieldCancellable: AnyCancellable? = nil
  private var _mtRevealTap: UITapGestureRecognizer? = nil
  private var _mtEndCancellable: AnyCancellable? = nil
  private weak var _mtEndHost: UIViewController? = nil
  // 圏外ドラフトのカード。表示専用（ドラフトがある時だけタッチを受ける）
  private var _mtDraftCancellable: AnyCancellable? = nil
  private weak var _mtDraftHost: UIViewController? = nil
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
      onSettings: { [weak self] in self?._mtShowSettings() },
      onCommandBlocks: { [weak self] in self?._mtShowCommandBlocks() },
      onShieldNow: { [weak self] in self?._mtShieldNow() },
      // サイドバーがある iPad / Mac では歯車をサイドバー側に出すので、タブバーには出さない
      showSettings: !_mtSupportsSidebar
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
    // 端末ビューの上インセットに加算される（LayoutConstraintManager）
    MTChrome.tabBarTopInset = MTTabBarHost.height

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

    // 圏外ドラフトのカード（表示専用。カードが出ている時だけタッチを受ける）
    let draftHost = UIHostingController(rootView: MTDraftOverlayView(onSend: { [weak self] lines in
      self?._mtSendDraftLines(lines)
    }))
    _mtAddOverlay(draftHost, into: view, bottom: view.keyboardLayoutGuide.topAnchor)
    _mtDraftHost = draftHost
    _mtDraftCancellable = MTDraftStore.shared.$drafts.sink { [weak self] _ in
      self?._mtApplyDraftInteractivity()
    }

    // 危険コマンドの長押しリング。確定中だけ全画面でタッチを受けるモーダル。
    // belowTabBar=false で全画面を覆うが、pending の間だけ true にするので
    // 通常時はタブバー・端末へタッチが通る（下の sink 参照）。
    let ringHost = UIHostingController(rootView: MTDangerRingView())
    _mtAddOverlay(ringHost, into: view, belowTabBar: false, bottom: view.bottomAnchor)
    _mtRingHost = ringHost

    // スクラブ中の読み取り専用オーバーレイ（07 #01）。スクラブ中だけタッチを受ける
    let scrubHost = UIHostingController(rootView: MTScrubOverlayView())
    _mtAddOverlay(scrubHost, into: view, bottom: view.keyboardLayoutGuide.topAnchor)
    _mtScrubCancellable = MTScreenHistory.shared.$scrubbing.sink { [weak scrubHost] snapshot in
      scrubHost?.view.isUserInteractionEnabled = snapshot != nil
    }

    // 画面スナップショットを定期的に撮る（07 #01）
    _mtSnapshotTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
      self?._mtTakeSnapshot(reason: "定期")
    }

    // 接続終了の案内（exit 後に固まって見える問題への対応）
    let endHost = UIHostingController(rootView: MTSessionEndView(
      onReconnect: { [weak self] command in
        self?._newShellAction(command: command, animated: false)
      },
      onNewConnection: { [weak self] in self?._mtShowConnectSheet() },
      onCloseTab: { [weak self] in self?._closeCurrentSpace() }
    ))
    _mtAddOverlay(endHost, into: view, bottom: view.bottomAnchor)
    _mtEndHost = endHost
    // 案内の有無が変わったときも、タブを切り替えたときも、タッチ可否を再計算する
    _mtEndCancellable = MTSessionEndCenter.shared.$ended.sink { [weak self] _ in
      DispatchQueue.main.async { self?._mtApplyEndView() }
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(_mtRemoteSessionDidEnd(_:)),
      name: .MTRemoteSessionDidEnd, object: nil)

    // 覗き見防止（07 #08）: 無操作が続いたら本番ホストのタブを伏せる
    _mtShieldTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      guard let self else { return }
      MTShieldCenter.shared.checkIdle(currentKey: self._currentKey)
    }
    _mtShieldCancellable = MTShieldCenter.shared.$shielded.sink { [weak self] _ in
      DispatchQueue.main.async { self?._mtApplyShield() }
    }
    // 伏せている間のタップで戻す
    let revealTap = UITapGestureRecognizer(target: self, action: #selector(_mtRevealTapped))
    revealTap.delegate = self
    _mtRevealTap = revealTap
    view.addGestureRecognizer(revealTap)
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
    // 既定は非インタラクティブ（_mtAddOverlay が設定済み）。長押し待ちの間だけ受ける
    _mtRingCancellable = MTDangerGuard.shared.$pending.sink { [weak ringHost] pending in
      ringHost?.view.isUserInteractionEnabled = pending != nil
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
    }
  }

  /// 終了案内のタッチ可否を、現在タブに案内が出ているかで決める
  private func _mtApplyEndView() {
    let show = _currentKey.map { MTSessionEndCenter.shared.ended(for: $0) != nil } ?? false
    _mtEndHost?.view.isUserInteractionEnabled = show
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
    currentTerm()?.resignInput()
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
      onSelect: { [weak self] key in self?._moveToShell(key: key) },
      onNew: { [weak self] in
        // 一覧シートの dismiss と競合しないよう、閉じ終わってから接続シートを開く
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
          self?._mtShowConnectSheet()
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
        self?._newShellAction(command: "\(kind.command) \(alias)", animated: true)
      },
      onNewConnection: { [weak self] in self?._mtShowConnectSheet() },
      onRename: { [weak self] key in self?._mtRenameSession(key) },
      onClose: { [weak self] key in self?._mtCloseSession(key) },
      onSettings: { [weak self] in self?._mtShowSettings() },
      onCommandBlocks: { [weak self] in self?._mtShowCommandBlocks() },
      onShieldNow: { [weak self] in self?._mtShieldNow() }
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
    currentTerm()?.resignInput()
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
    MTSessionStateCenter.shared.clear(for: key)
    MTSessionsStore.shared.setTitle(nil, for: key)
    if let idx = _viewportsKeys.firstIndex(of: key) {
      _viewportsKeys.remove(at: idx)
    }
    _mtTabBarUpdate()
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
            // mosh/ssh はエイリアス 1 語で BKHosts の設定を解決する
            self?._newShellAction(command: "\(kind.command) \(alias)", animated: true)
          }
        },
        onLocalShell: { [weak self] in
          self?.dismiss(animated: true) {
            self?.newShellAction()
          }
        },
        onClose: { [weak self] in
          self?.dismiss(animated: true)
        }
      )
    }
    // NavView は navController を画面に組み込まないため、設定画面と同じく
    // UINavigationController 自体を present する（push・ナビバーが機能する）
    let content = UIHostingController(rootView: rootView)
    navController.setViewControllers([content], animated: false)
    navController.overrideUserInterfaceStyle = MTThemeStore.shared.overrideInterfaceStyle ?? .unspecified
    navController.modalPresentationStyle = .pageSheet
    currentTerm()?.resignInput()
    present(navController, animated: true)
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
    _mtDraftHost?.view.isUserInteractionEnabled = hasDrafts
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
    _attachInputToCurrentTerm()

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
    }
  }
  
  @objc func focusOnShellAction() {
    KBTracker.shared.input?.reset()
    _focusOnShell()
  }
  
  @objc public func scaleWithPich(_ pinch: UIPinchGestureRecognizer) {
    currentTerm()?.scaleWithPich(pinch)
  }
  
  private func _newShellAction(command: String = "", animated: Bool = true) {
    let params = MCPParams()
    if !command.isEmpty {
      params.initialCommand = command
      // MoshTerm: 接続先ホストをセッションに紐付ける（額縁・安全機能が参照、07 #02/#03/#04）
      _mtPendingAlias = MTHostContext.parseAlias(fromCommand: command)
    }
    let payload = MCPSessionPayload(params: params)
    _createTerminal(userActivity: nil, animated: animated, sessionPayload: payload)
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
      self._attachInputToCurrentTerm()
      self._spaceControllerAnimating = false
    }
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
