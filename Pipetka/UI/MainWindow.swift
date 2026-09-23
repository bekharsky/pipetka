import AppKit
import SwiftUI

private final class ToolbarHitAreaView: NSView {
  weak var targetButton: NSButton?

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard bounds.contains(point) else { return nil }
    return targetButton
  }
}

final class MainWindow: NSWindow, NSToolbarDelegate {
  private enum ToolbarIdentifier {
    static let main = NSToolbar.Identifier("com.kharion.pipetka.main-toolbar")
    static let onTop = NSToolbarItem.Identifier("com.kharion.pipetka.toolbar.on-top")
    static let importItem = NSToolbarItem.Identifier("com.kharion.pipetka.toolbar.import")
    static let pick = NSToolbarItem.Identifier("com.kharion.pipetka.toolbar.pick")
    static let pickGroup = NSToolbarItem.Identifier("com.kharion.pipetka.toolbar.pick-group")
    static let clearHistory = NSToolbarItem.Identifier("com.kharion.pipetka.toolbar.clear-history")
    static let spacer = NSToolbarItem.Identifier.flexibleSpace
  }

  let store = PipetkaStore()
  private weak var pinToolbarItem: NSToolbarItem?
  private weak var countLabel: NSTextField?
  private var titleAccessoryController: NSTitlebarAccessoryViewController?
  private weak var pinToolbarButton: NSButton?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func awakeFromNib() {
    let rootView = MainWindowRootView(store: store)
    let hostingController = NSHostingController(rootView: rootView)
    let windowFrame = frame
    contentViewController = hostingController
    setFrame(windowFrame, display: true)

    configureWindow()

    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.configureMainWindow(window: self)
    }

    super.awakeFromNib()
  }

  private func configureWindow() {
    styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    title = "Pipetka"
    updateTitlebarCount(store.history.count)
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    backgroundColor = .windowBackgroundColor
    isOpaque = false
    hasShadow = true
    setContentSize(NSSize(width: 420, height: 500))
    minSize = NSSize(width: 380, height: 380)
    standardWindowButton(.miniaturizeButton)?.isEnabled = false
    standardWindowButton(.zoomButton)?.isEnabled = false
    setupTitleAccessory()
    setupToolbar()
    center()

    if #available(macOS 11.0, *) {
      toolbarStyle = .unified
      titlebarSeparatorStyle = .none
    }

  }

  func syncToolbarState() {
    pinToolbarItem?.image = toolbarImage(systemName: store.alwaysOnTop ? "pin.fill" : "pin")
    pinToolbarItem?.toolTip = store.alwaysOnTop ? "Disable On Top" : "Enable On Top"
    pinToolbarButton?.image = toolbarImage(systemName: store.alwaysOnTop ? "pin.fill" : "pin")
  }

  func updateTitlebarCount(_ count: Int) {
    countLabel?.stringValue = count == 1 ? "1 pick" : "\(count) picks"
  }

  func clearInitialFocus() {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.isVisible else { return }
      self.makeFirstResponder(nil)
    }
  }

  @objc
  private func handleToolbarToggleOnTop(_ sender: Any?) {
    store.requestAlwaysOnTopToggle()
  }

  @objc
  private func handleToolbarImport(_ sender: Any?) {
    store.requestImport()
  }

  @objc
  private func handleToolbarPick(_ sender: Any?) {
    store.requestPick()
  }

  @objc
  private func handleToolbarClearHistory(_ sender: Any?) {
    store.clearAll()
  }

  private func toolbarImage(systemName: String, tintColor: NSColor? = nil) -> NSImage? {
    let configuredImage: NSImage
    if #available(macOS 11.0, *) {
      guard let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else {
        return nil
      }
      let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
      configuredImage = image.withSymbolConfiguration(config) ?? image
    } else {
      guard let image = PlatformSymbol.image(systemName: systemName) else {
        return nil
      }
      configuredImage = image
    }

    guard let tintColor else {
      return configuredImage
    }

    let tintedImage = configuredImage.copy() as? NSImage ?? configuredImage
    tintedImage.lockFocus()
    defer { tintedImage.unlockFocus() }

    tintColor.set()
    NSRect(origin: .zero, size: tintedImage.size).fill(using: .sourceAtop)
    tintedImage.isTemplate = false
    return tintedImage
  }

  private func setupToolbar() {
    let toolbar = NSToolbar(identifier: ToolbarIdentifier.main)
    toolbar.delegate = self
    // Each custom toolbar view already draws its own label. Asking AppKit to
    // draw labels as well produces a duplicate label on macOS 26.
    toolbar.displayMode = .iconOnly
    toolbar.sizeMode = .regular
    toolbar.allowsUserCustomization = false
    toolbar.autosavesConfiguration = false
    self.toolbar = toolbar
    syncToolbarState()
  }

  private func setupTitleAccessory() {
    guard titleAccessoryController == nil else { return }

    let titleLabel = NSTextField(labelWithString: "Pipetka")
    titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    titleLabel.textColor = .labelColor
    titleLabel.lineBreakMode = .byTruncatingTail

    let countLabel = NSTextField(labelWithString: "")
    countLabel.font = .systemFont(ofSize: 12, weight: .regular)
    countLabel.textColor = .secondaryLabelColor
    countLabel.lineBreakMode = .byTruncatingTail
    self.countLabel = countLabel

    let stack = NSStackView(views: [titleLabel, countLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 88, height: 30))
    container.translatesAutoresizingMaskIntoConstraints = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)

    NSLayoutConstraint.activate([
      container.widthAnchor.constraint(equalToConstant: 88),
      container.heightAnchor.constraint(equalToConstant: 30),
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
    ])

    let accessory = NSTitlebarAccessoryViewController()
    accessory.view = container
    accessory.layoutAttribute = .left
    addTitlebarAccessoryViewController(accessory)
    titleAccessoryController = accessory

    updateTitlebarCount(store.history.count)
  }

  private func makeToolbarItem(
    identifier: NSToolbarItem.Identifier,
    label: String,
    symbolName: String,
    action: Selector,
    tintColor: NSColor? = nil
  ) -> NSToolbarItem {
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.label = label
    item.paletteLabel = label
    item.toolTip = label
    item.image = toolbarImage(systemName: symbolName, tintColor: tintColor)
    item.visibilityPriority = .high

    if #available(macOS 26.0, *) {
      item.target = self
      item.action = action

      if identifier == ToolbarIdentifier.onTop {
        pinToolbarItem = item
      }

      syncToolbarState()

      return item
    }

    let container = makeToolbarControl(
      label: label,
      symbolName: symbolName,
      action: action,
      tintColor: tintColor
    )

    item.view = container

    if identifier == ToolbarIdentifier.onTop {
      pinToolbarItem = item
    }

    return item
  }

  private func makeToolbarControl(
    label: String,
    symbolName: String,
    action: Selector,
    tintColor: NSColor? = nil
  ) -> ToolbarHitAreaView {
    let button = NSButton(image: toolbarImage(systemName: symbolName, tintColor: tintColor) ?? NSImage(), target: self, action: action)
    button.bezelStyle = .texturedRounded
    button.controlSize = .regular
    button.isBordered = true
    button.imagePosition = .imageOnly
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setButtonType(.momentaryPushIn)
    button.imageScaling = .scaleNone

    let titleLabel = NSTextField(labelWithString: label)
    titleLabel.font = .systemFont(ofSize: 10, weight: .regular)
    titleLabel.textColor = .secondaryLabelColor
    titleLabel.alignment = .center
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView(views: [button, titleLabel])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 1
    stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    let container = ToolbarHitAreaView(frame: NSRect(x: 0, y: 0, width: 50, height: 40))
    container.translatesAutoresizingMaskIntoConstraints = false
    container.targetButton = button
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)

    NSLayoutConstraint.activate([
      container.widthAnchor.constraint(equalToConstant: 50),
      container.heightAnchor.constraint(equalToConstant: 40),
      stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      button.widthAnchor.constraint(equalToConstant: 44),
      button.heightAnchor.constraint(equalToConstant: 32)
    ])

    if label == "On Top" {
      pinToolbarButton = button
    }

    return container
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      ToolbarIdentifier.spacer,
      ToolbarIdentifier.onTop,
      ToolbarIdentifier.importItem,
      ToolbarIdentifier.pickGroup,
      ToolbarIdentifier.clearHistory
    ]
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      ToolbarIdentifier.spacer,
      ToolbarIdentifier.onTop,
      ToolbarIdentifier.importItem,
      ToolbarIdentifier.clearHistory,
      ToolbarIdentifier.pickGroup
    ]
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    switch itemIdentifier {
    case ToolbarIdentifier.pickGroup:
      return makePickToolbarGroup()
    case ToolbarIdentifier.onTop:
      return makeToolbarItem(
        identifier: itemIdentifier,
        label: "On Top",
        symbolName: store.alwaysOnTop ? "pin.fill" : "pin",
        action: #selector(handleToolbarToggleOnTop(_:))
      )
    case ToolbarIdentifier.importItem:
      return makeToolbarItem(
        identifier: itemIdentifier,
        label: "Import",
        symbolName: "folder.badge.plus",
        action: #selector(handleToolbarImport(_:))
      )
    case ToolbarIdentifier.clearHistory:
      return makeToolbarItem(
        identifier: itemIdentifier,
        label: "Clear History",
        symbolName: "eraser",
        action: #selector(handleToolbarClearHistory(_:))
      )
    default:
      return nil
    }
  }

  private func makePickToolbarGroup() -> NSToolbarItemGroup {
    let pickItem = makeToolbarItem(
      identifier: ToolbarIdentifier.pick,
      label: "Pick",
      symbolName: "eyedropper.full",
      action: #selector(handleToolbarPick(_:)),
      tintColor: .controlAccentColor
    )
    let group = NSToolbarItemGroup(itemIdentifier: ToolbarIdentifier.pickGroup)
    group.subitems = [pickItem]
    group.label = "Pick"
    group.paletteLabel = "Pick"
    group.toolTip = "Pick"
    group.visibilityPriority = .high
    return group
  }
}
