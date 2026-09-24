import ApplicationServices
import Cocoa
import PipetkaCore
import ServiceManagement

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
  private enum PickerInvocationSource {
    case mainWindow
    case statusBar
  }

  @IBOutlet weak var applicationMenu: NSMenu!
  @IBOutlet weak var mainWindow: MainWindow!

  private static let showWindowAfterStatusBarPickKey = "ShowWindowAfterStatusBarPick"
  private static let screenCaptureRequestAttemptedKey = "ScreenCaptureRequestAttempted"

  private var isMainWindowAlwaysOnTop = false
  private var hasRequestedScreenCaptureAccessThisLaunch = false
  private var pickerInvocationSource: PickerInvocationSource = .mainWindow
  private var shouldRestoreMainWindowAfterStatusBarPick = false
  private var isRunningUnitTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }
  private var isUITesting: Bool {
    ProcessInfo.processInfo.arguments.contains("-ui-testing")
      || ProcessInfo.processInfo.environment["PIPETKA_UI_TESTING"] == "1"
  }
  private var showsWindowAfterStatusBarPick = UserDefaults.standard.bool(
    forKey: AppDelegate.showWindowAfterStatusBarPickKey
  )
  private var isLaunchAtLoginEnabled = LaunchAtLoginController.isEnabled
  private var aboutWindowController: NSWindowController?
  private weak var alwaysOnTopMenuItem: NSMenuItem?
  private weak var launchAtLoginMenuItem: NSMenuItem?
  private lazy var screenColorPicker = ScreenColorPicker(
    hideWindow: { [weak self] in
      self?.handlePickerWindowHide()
    },
    showWindow: { [weak self] in
      self?.handlePickerWindowRestore()
    },
    onPick: { [weak self] payload in
      self?.handlePickedColor(payload)
    },
    usesTestSampling: isUITesting
  )
  private lazy var statusBarController = StatusBarController(
    onPick: { [weak self] in
      self?.startPicker(from: .statusBar)
    },
    onShow: { [weak self] in
      self?.showMainWindow()
    },
    showsWindowAfterPick: showsWindowAfterStatusBarPick,
    onShowWindowAfterPickChange: { [weak self] value in
      self?.setShowsWindowAfterStatusBarPick(value)
    },
    isLaunchAtLoginEnabled: isLaunchAtLoginEnabled,
    onLaunchAtLoginChange: { [weak self] value in
      self?.setLaunchAtLoginEnabled(value)
    },
    onAbout: { [weak self] in
      self?.showAbout(nil)
    },
    onQuit: { [weak self] in
      self?.quitApp(nil)
    },
    onCopy: { [weak self] text in
      self?.copyText(text)
    }
  )

  func applicationDidFinishLaunching(_ notification: Notification) {
    applyDebugAppearanceOverride()
    configureApplicationIcon()
    configureApplicationMenu()
    refreshStatusBar()
    guard !isRunningUnitTests else {
      return
    }
    DispatchQueue.main.async { [weak self] in
      self?.showMainWindow()
    }
  }

  private func applyDebugAppearanceOverride() {
    #if DEBUG
    switch ProcessInfo.processInfo.environment["PIPETKA_APPEARANCE"]?.lowercased() {
    case "dark":
      NSApp.appearance = NSAppearance(named: .darkAqua)
    case "light":
      NSApp.appearance = NSAppearance(named: .aqua)
    default:
      break
    }
    #endif
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hideMainWindow()
    return false
  }

  func configureMainWindow(window: MainWindow) {
    window.delegate = self
    window.store.setAlwaysOnTop(isMainWindowAlwaysOnTop)
    window.syncToolbarState()
    window.updateTitlebarCount(window.store.history.count)
    applyMainWindowLevel()
    window.store.onPickRequested = { [weak self] in
      self?.startPicker(from: .mainWindow)
    }
    window.store.onImportRequested = { [weak self] in
      self?.importImagesFromToolbar(nil)
    }
    window.store.onAlwaysOnTopToggleRequested = { [weak self] in
      self?.toggleAlwaysOnTopFromToolbar(nil)
    }
    window.store.onRecentPicksChanged = { [weak self] picks in
      self?.statusBarController.updateRecentPicks(picks)
      self?.mainWindow?.updateTitlebarCount(self?.mainWindow?.store.history.count ?? 0)
    }
    statusBarController.updateRecentPicks(window.store.currentRecentPickItems())
  }

  private func configureApplicationMenu() {
    let appName = resolvedApplicationName()
    replaceAppNamePlaceholders(in: NSApp.mainMenu, with: appName)

    if let appMenuItem = NSApp.mainMenu?.items.first {
      appMenuItem.title = appName
      appMenuItem.submenu?.title = appName
    }

    if let aboutItem = applicationMenu.items.first(where: { $0.title == "About \(appName)" }) {
      aboutItem.action = #selector(showAbout(_:))
      aboutItem.target = self
    }

    configureLaunchAtLoginApplicationMenuItem()

    if let hideIndex = applicationMenu.items.firstIndex(where: { $0.keyEquivalent == "h" }) {
      let hideItem = applicationMenu.items[hideIndex]
      hideItem.title = "Hide \(appName)"
      hideItem.action = #selector(NSApplication.hide(_:))
      hideItem.target = NSApp
    }

    if let quitIndex = applicationMenu.items.firstIndex(where: { $0.keyEquivalent == "q" }) {
      let quitItem = applicationMenu.items[quitIndex]
      quitItem.title = "Quit \(appName)"
      quitItem.action = #selector(quitApp(_:))
      quitItem.target = self
    }

    NSApp.mainMenu?.items.removeAll { $0.title == "Edit" }
    configureToolsMenu()
  }

  @objc
  private func quitApp(_ sender: Any?) {
    NSApp.terminate(nil)
  }

  @objc
  private func hideWindowCommand(_ sender: Any?) {
    hideMainWindow()
  }

  @objc
  private func showAbout(_ sender: Any?) {
    let windowController = aboutWindowController ?? makeAboutWindowController()
    aboutWindowController = windowController
    windowController.showWindow(nil)
    windowController.window?.center()
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc
  func startPickerFromToolbar(_ sender: Any?) {
    startPicker(from: .mainWindow)
  }

  private func startPicker(from source: PickerInvocationSource) {
    guard ensureScreenCaptureAccess() else {
      return
    }

    pickerInvocationSource = source
    shouldRestoreMainWindowAfterStatusBarPick = false
    screenColorPicker.start()
  }

  @objc
  func importImagesFromToolbar(_ sender: Any?) {
    guard
      let store = mainWindow?.store,
      let window = mainWindow
    else {
      return
    }

    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.resolvesAliases = true
    panel.prompt = "Import"
    panel.message = "Choose image files or folders to build imported palettes."

    let nestedFoldersButton = NSButton(checkboxWithTitle: "Analyze nested folders", target: nil, action: nil)
    nestedFoldersButton.state = .off
    panel.accessoryView = nestedFoldersButton

    showMainWindow()
    NSApp.activate(ignoringOtherApps: true)
    panel.beginSheetModal(for: window) { response in
      guard response == .OK else {
        return
      }

      store.importSelectedItems(
        at: panel.urls,
        includesNestedFolders: nestedFoldersButton.state == .on
      )
    }
  }

  @objc
  func toggleAlwaysOnTopFromToolbar(_ sender: Any?) {
    isMainWindowAlwaysOnTop.toggle()
    mainWindow?.store.setAlwaysOnTop(isMainWindowAlwaysOnTop)
    mainWindow?.syncToolbarState()
    alwaysOnTopMenuItem?.state = isMainWindowAlwaysOnTop ? .on : .off
    applyMainWindowLevel()
  }

  @objc
  private func copyHistoryAs(_ sender: NSMenuItem) {
    guard
      let rawValue = sender.representedObject as? Int,
      let format = PaletteExportFormat(rawValue: rawValue),
      let history = mainWindow?.store.history,
      !history.isEmpty
    else {
      return
    }

    copyText(
      exportColors(
        history,
        format: format,
        cssColorSpace: mainWindow?.store.cssColorSpace ?? .sRGB
      )
    )
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(toggleAlwaysOnTopFromToolbar(_:)):
      menuItem.state = isMainWindowAlwaysOnTop ? .on : .off
      return true
    case #selector(copyHistoryAs(_:)):
      return !(mainWindow?.store.history.isEmpty ?? true)
    default:
      return true
    }
  }

  private func handlePickedColor(_ payload: PickedColorPayload) {
    mainWindow?.store.addPick(
      color: payload.color,
      previewPng: payload.previewPng
    )
  }

  private func handlePickerWindowHide() {
    switch pickerInvocationSource {
    case .mainWindow:
      hideMainWindow()
    case .statusBar:
      guard
        let window = mainWindow,
        window.isVisible,
        window.isKeyWindow || window.isMainWindow
      else {
        return
      }

      shouldRestoreMainWindowAfterStatusBarPick = true
      hideMainWindow()
    }
  }

  private func handlePickerWindowRestore() {
    defer {
      pickerInvocationSource = .mainWindow
      shouldRestoreMainWindowAfterStatusBarPick = false
    }

    switch pickerInvocationSource {
    case .mainWindow:
      showMainWindow()
    case .statusBar:
      guard showsWindowAfterStatusBarPick || shouldRestoreMainWindowAfterStatusBarPick else {
        return
      }
      showMainWindowWithoutActivating()
    }
  }

  private func setShowsWindowAfterStatusBarPick(_ value: Bool) {
    showsWindowAfterStatusBarPick = value
    UserDefaults.standard.set(value, forKey: Self.showWindowAfterStatusBarPickKey)
    statusBarController.setShowsWindowAfterPick(value)
  }

  private func setLaunchAtLoginEnabled(_ value: Bool) {
    guard value != isLaunchAtLoginEnabled else {
      refreshLaunchAtLoginMenuState()
      return
    }

    do {
      try LaunchAtLoginController.setEnabled(value)
      isLaunchAtLoginEnabled = value
      refreshLaunchAtLoginMenuState()
    } catch {
      refreshLaunchAtLoginMenuState()
      showLaunchAtLoginError(error)
    }
  }

  @objc
  private func toggleLaunchAtLogin(_ sender: Any?) {
    setLaunchAtLoginEnabled(!isLaunchAtLoginEnabled)
  }

  private func copyText(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  private func configureApplicationIcon() {
    guard let icon = resolvedApplicationIcon() else {
      return
    }
    NSApp.applicationIconImage = icon
  }

  private func resolvedApplicationIcon() -> NSImage? {
    if let resourcePath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
       let icon = NSImage(contentsOfFile: resourcePath) {
      return icon
    }

    return NSImage(named: "AppIcon")
  }

  private func makeAboutWindowController() -> NSWindowController {
    let contentSize = NSSize(width: 420, height: 320)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "About Pipetka"
    window.isReleasedWhenClosed = false
    window.center()

    let contentView = NSView(frame: NSRect(origin: .zero, size: contentSize))
    contentView.translatesAutoresizingMaskIntoConstraints = false
    window.contentView = contentView

    let iconView = NSImageView()
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.image = resolvedApplicationIcon()
    iconView.imageScaling = .scaleProportionallyUpOrDown

    let appNameLabel = NSTextField(labelWithString: "Pipetka")
    appNameLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
    appNameLabel.alignment = .center

    let versionLabel = NSTextField(labelWithString: aboutVersionText())
    versionLabel.font = NSFont.systemFont(ofSize: 12)
    versionLabel.textColor = .secondaryLabelColor
    versionLabel.alignment = .center

    let descriptionLabel = NSTextField(
      wrappingLabelWithString: "Advanced color picker for sampling, naming, and exporting precise palettes."
    )
    descriptionLabel.font = NSFont.systemFont(ofSize: 13)
    descriptionLabel.textColor = .labelColor
    descriptionLabel.alignment = .center
    descriptionLabel.maximumNumberOfLines = 0

    let authorLabel = NSTextField(labelWithString: "Author: Sergey Bekharskiy")
    authorLabel.font = NSFont.systemFont(ofSize: 12)
    authorLabel.textColor = .secondaryLabelColor
    authorLabel.alignment = .center

    let copyrightLabel = NSTextField(labelWithString: aboutCopyrightText())
    copyrightLabel.font = NSFont.systemFont(ofSize: 11)
    copyrightLabel.textColor = .secondaryLabelColor
    copyrightLabel.alignment = .center

    let attributionTitle = NSTextField(labelWithString: "Color naming")
    attributionTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

    let attributionLabel = NSTextField(wrappingLabelWithString: NamedColorLookup.aboutAttribution)
    attributionLabel.font = NSFont.systemFont(ofSize: 12)
    attributionLabel.textColor = .labelColor
    attributionLabel.maximumNumberOfLines = 0

    let stack = NSStackView(views: [
      iconView,
      appNameLabel,
      versionLabel,
      descriptionLabel,
      authorLabel,
      copyrightLabel,
      attributionTitle,
      attributionLabel
    ])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 10
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
    stack.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(stack)

    attributionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    attributionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    attributionTitle.setContentHuggingPriority(.defaultLow, for: .horizontal)
    descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: contentView.topAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 64),
      iconView.heightAnchor.constraint(equalToConstant: 64),
      descriptionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
      attributionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 340)
    ])

    return NSWindowController(window: window)
  }

  private func aboutVersionText() -> String {
    let bundle = Bundle.main
    let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let buildVersion = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

    switch (shortVersion?.isEmpty == false ? shortVersion : nil, buildVersion?.isEmpty == false ? buildVersion : nil) {
    case let (short?, build?) where short != build:
      return "Version \(short) (\(build))"
    case let (short?, _):
      return "Version \(short)"
    case let (_, build?):
      return "Build \(build)"
    default:
      return "Color picker and palette utility"
    }
  }

  private func aboutCopyrightText() -> String {
    (Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nonEmpty ?? "Copyright © 2026 Kharion. All rights reserved."
  }

  private func showMainWindow() {
    guard let window = mainWindow else {
      return
    }

    applyMainWindowLevel()
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    window.makeKeyAndOrderFront(nil)
    window.clearInitialFocus()
  }

  private func showMainWindowWithoutActivating() {
    guard let window = mainWindow else {
      return
    }

    applyMainWindowLevel()
    window.orderFront(nil)
    window.clearInitialFocus()
  }

  private func hideMainWindow() {
    mainWindow?.orderOut(nil)
  }

  private func applyMainWindowLevel() {
    guard let window = mainWindow else {
      return
    }

    window.level = isMainWindowAlwaysOnTop ? .floating : .normal
  }

  private func refreshStatusBar() {
    statusBarController.install()
  }

  private func configureToolsMenu() {
    guard let mainMenu = NSApp.mainMenu else {
      return
    }

    mainMenu.items.removeAll { $0.title == "Tools" }

    let toolsMenu = NSMenu(title: "Tools")

    let pickItem = NSMenuItem(
      title: "Pick Color",
      action: #selector(startPickerFromToolbar(_:)),
      keyEquivalent: "p"
    )
    pickItem.keyEquivalentModifierMask = [.command]
    pickItem.target = self
    toolsMenu.addItem(pickItem)

    let importItem = NSMenuItem(
      title: "Import...",
      action: #selector(importImagesFromToolbar(_:)),
      keyEquivalent: "i"
    )
    importItem.keyEquivalentModifierMask = [.command]
    importItem.target = self
    toolsMenu.addItem(importItem)

    let closeWindowItem = NSMenuItem(
      title: "Close Window",
      action: #selector(hideWindowCommand(_:)),
      keyEquivalent: "w"
    )
    closeWindowItem.keyEquivalentModifierMask = [.command]
    closeWindowItem.target = self
    toolsMenu.addItem(closeWindowItem)

    let alwaysOnTopItem = NSMenuItem(
      title: "Always on Top",
      action: #selector(toggleAlwaysOnTopFromToolbar(_:)),
      keyEquivalent: ""
    )
    alwaysOnTopItem.target = self
    alwaysOnTopItem.state = isMainWindowAlwaysOnTop ? .on : .off
    alwaysOnTopMenuItem = alwaysOnTopItem
    toolsMenu.addItem(alwaysOnTopItem)

    toolsMenu.addItem(NSMenuItem.separator())

    let copyHistoryItem = NSMenuItem(title: "Copy History As", action: nil, keyEquivalent: "")
    let copyHistoryMenu = NSMenu(title: "Copy History As")
    for format in PaletteExportFormat.allCases {
      let item = NSMenuItem(
        title: format.label,
        action: #selector(copyHistoryAs(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = format.rawValue
      copyHistoryMenu.addItem(item)
    }
    copyHistoryItem.submenu = copyHistoryMenu
    toolsMenu.addItem(copyHistoryItem)

    let toolsMenuItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
    toolsMenuItem.submenu = toolsMenu
    mainMenu.insertItem(toolsMenuItem, at: min(1, mainMenu.numberOfItems))
  }

  private func configureLaunchAtLoginApplicationMenuItem() {
    applicationMenu.items.removeAll { $0.action == #selector(toggleLaunchAtLogin(_:)) }

    let item = NSMenuItem(
      title: "Launch at Login",
      action: #selector(toggleLaunchAtLogin(_:)),
      keyEquivalent: ""
    )
    item.target = self
    item.state = isLaunchAtLoginEnabled ? .on : .off

    let insertionIndex: Int
    if let preferencesIndex = applicationMenu.items.firstIndex(where: { $0.title == "Preferences…" }) {
      insertionIndex = preferencesIndex + 1
    } else if let servicesIndex = applicationMenu.items.firstIndex(where: { $0.title == "Services" }) {
      insertionIndex = servicesIndex
    } else {
      insertionIndex = min(2, applicationMenu.numberOfItems)
    }

    applicationMenu.insertItem(item, at: insertionIndex)
    launchAtLoginMenuItem = item
    refreshLaunchAtLoginMenuState()
  }

  private func refreshLaunchAtLoginMenuState() {
    isLaunchAtLoginEnabled = LaunchAtLoginController.isEnabled
    launchAtLoginMenuItem?.state = isLaunchAtLoginEnabled ? .on : .off
    statusBarController.setLaunchAtLoginEnabled(isLaunchAtLoginEnabled)
  }

  private func showLaunchAtLoginError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Launch at Login could not be updated"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func replaceAppNamePlaceholders(in menu: NSMenu?, with appName: String) {
    guard let menu else {
      return
    }

    menu.title = menu.title.replacingOccurrences(of: "APP_NAME", with: appName)

    for item in menu.items {
      item.title = item.title.replacingOccurrences(of: "APP_NAME", with: appName)
      replaceAppNamePlaceholders(in: item.submenu, with: appName)
    }
  }

  private func resolvedApplicationName() -> String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nonEmpty ?? "Pipetka"
  }

  private func ensureScreenCaptureAccess() -> Bool {
    if isUITesting {
      return true
    }

    guard #available(macOS 10.15, *) else {
      return true
    }

    if CGPreflightScreenCaptureAccess() {
      UserDefaults.standard.removeObject(forKey: Self.screenCaptureRequestAttemptedKey)
      return true
    }

    let requestWasAlreadyAttempted = hasRequestedScreenCaptureAccessThisLaunch
      || UserDefaults.standard.bool(forKey: Self.screenCaptureRequestAttemptedKey)
    guard !requestWasAlreadyAttempted else {
      showScreenAccessSettingsAlert()
      return false
    }

    hasRequestedScreenCaptureAccessThisLaunch = true
    // CGRequestScreenCaptureAccess presents a system modal. Persist the fact
    // that we have already asked so a denial cannot turn into a prompt loop
    // after the app is relaunched or the downloaded bundle is replaced.
    UserDefaults.standard.set(true, forKey: Self.screenCaptureRequestAttemptedKey)
    NSApp.activate(ignoringOtherApps: true)
    _ = CGRequestScreenCaptureAccess()

    if CGPreflightScreenCaptureAccess() {
      UserDefaults.standard.removeObject(forKey: Self.screenCaptureRequestAttemptedKey)
      return true
    }

    showMainWindow()
    return false
  }

  @available(macOS 10.15, *)
  private func showScreenAccessSettingsAlert() {
    showMainWindow()

    let alert = NSAlert()
    alert.messageText = "Screen access is not enabled"
    alert.informativeText = "Allow Pipetka in System Settings → Privacy & Security → Screen Recording, then try Pick again."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Quit Pipetka")
    alert.addButton(withTitle: "Not Now")

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      openScreenAccessSettings()
    case .alertSecondButtonReturn:
      NSApp.terminate(nil)
    default:
      break
    }
  }

  @available(macOS 10.15, *)
  private func openScreenAccessSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
      return
    }

    NSWorkspace.shared.open(url)
  }
}

private extension String {
  var nonEmpty: String? {
    isEmpty ? nil : self
  }
}

enum LaunchAtLoginController {
  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  static func setEnabled(_ enabled: Bool) throws {
    if enabled {
      if SMAppService.mainApp.status != .enabled {
        try SMAppService.mainApp.register()
      }
    } else if SMAppService.mainApp.status == .enabled {
      try SMAppService.mainApp.unregister()
    }
  }
}
