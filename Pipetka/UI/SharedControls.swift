import AppKit
import SwiftUI

struct CardContainer<Content: View>: View {
  @ViewBuilder let content: () -> Content
  let contentPadding: CGFloat

  init(contentPadding: CGFloat = 10, @ViewBuilder content: @escaping () -> Content) {
    self.contentPadding = contentPadding
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
    }
    .padding(contentPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(PlatformColor.cardBackground)
    .cornerRadius(14)
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(PlatformColor.hairlineBorder, lineWidth: 1)
    )
  }
}

struct PagerButton: View {
  let symbolName: String
  let fallbackText: String
  let toolTip: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      SymbolView(symbolName: symbolName, fallbackText: fallbackText)
        .frame(width: 20, height: 20)
    }
    .buttonStyle(.plain)
    .help(toolTip)
    .accessibilityLabel(toolTip)
  }
}

struct SmallIconButton: View {
  let symbolName: String
  let fallbackText: String
  let toolTip: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      SymbolView(symbolName: symbolName, fallbackText: fallbackText)
        .foregroundColor(.secondary)
        .frame(width: 24, height: 24)
    }
    .buttonStyle(.plain)
    .help(toolTip)
    .accessibilityLabel(toolTip)
  }
}

struct SymbolView: View {
  let symbolName: String
  let fallbackText: String

  var body: some View {
    if let image = PlatformSymbol.image(systemName: symbolName) {
      Image(nsImage: image)
        .renderingMode(.template)
    } else {
      Text(fallbackText)
        .font(.system(size: 11, weight: .semibold))
    }
  }
}

struct MenuButtonItem {
  let title: String
  let action: () -> Void
}

struct NativeButton: NSViewRepresentable {
  let title: String
  let controlSize: NSControl.ControlSize
  var isEnabled: Bool = true
  let action: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.handlePress(_:)))
    button.bezelStyle = .rounded
    button.controlSize = controlSize
    button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
    button.isEnabled = isEnabled
    return button
  }

  func updateNSView(_ nsView: NSButton, context: Context) {
    nsView.title = title
    nsView.controlSize = controlSize
    nsView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
    nsView.isEnabled = isEnabled
    context.coordinator.action = action
  }

  final class Coordinator: NSObject {
    var action: () -> Void

    init(action: @escaping () -> Void) {
      self.action = action
    }

    @objc
    func handlePress(_ sender: NSButton) {
      action()
    }
  }
}

struct MenuButton: NSViewRepresentable {
  let title: String
  let controlSize: NSControl.ControlSize
  var isEnabled: Bool = true
  let items: [MenuButtonItem]

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
    button.bezelStyle = .rounded
    button.controlSize = controlSize
    button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
    button.isEnabled = isEnabled
    return button
  }

  func updateNSView(_ nsView: NSButton, context: Context) {
    nsView.title = title
    nsView.controlSize = controlSize
    nsView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
    nsView.isEnabled = isEnabled
    context.coordinator.items = items
  }

  final class Coordinator: NSObject {
    var items: [MenuButtonItem] = []

    @objc
    func showMenu(_ sender: NSButton) {
      let menu = NSMenu()
      for item in items {
        let menuItem = NSMenuItem(title: item.title, action: #selector(handleItem(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = Box(item)
        menu.addItem(menuItem)
      }
      let point = NSPoint(x: 0, y: sender.bounds.maxY + 6)
      menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc
    private func handleItem(_ sender: NSMenuItem) {
      guard let box = sender.representedObject as? Box else {
        return
      }
      box.item.action()
    }

    final class Box: NSObject {
      let item: MenuButtonItem

      init(_ item: MenuButtonItem) {
        self.item = item
      }
    }
  }
}

enum PlatformSymbol {
  static func image(systemName: String) -> NSImage? {
    if #available(macOS 11.0, *) {
      let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
      let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
      return image?.withSymbolConfiguration(config)
    }
    return nil
  }
}

enum PlatformColor {
  // Keep AppKit's semantic colors dynamic. Converting them to RGB here would
  // freeze their value for one appearance and can leave white text on a white
  // surface after macOS switches to Dark Mode.
  static let chromeBackground = color(from: .windowBackgroundColor)
  static let cardBackground = color(from: .controlBackgroundColor)
  static let rowBackground = color(from: .controlBackgroundColor)
  static let selectedSegmentBackground = color(from: .textBackgroundColor)
  static let previewPlaceholder = color(from: .underPageBackgroundColor)
  static let rowHover = Color.accentColor.opacity(0.12)
  static let hairlineBorder = color(from: .separatorColor)
  static let headerButtonForeground = color(
    from: NSColor(
      srgbRed: 0.31,
      green: 0.40,
      blue: 0.53,
      alpha: 1
    )
  )
  static let headerButtonHoverForeground = color(
    from: NSColor(
      srgbRed: 0.10,
      green: 0.35,
      blue: 0.74,
      alpha: 1
    )
  )
  static let headerButtonActiveForeground = color(
    from: NSColor(
      srgbRed: 0.05,
      green: 0.27,
      blue: 0.60,
      alpha: 1
    )
  )
  static let headerButtonHoverBackground = color(
    from: NSColor(
      srgbRed: 0.23,
      green: 0.58,
      blue: 0.98,
      alpha: 0.14
    )
  )
  static let headerButtonActiveBackground = color(
    from: NSColor(
      srgbRed: 0.23,
      green: 0.58,
      blue: 0.98,
      alpha: 0.26
    )
  )
  static let headerButtonHoverBorder = color(
    from: NSColor(
      srgbRed: 0.13,
      green: 0.46,
      blue: 0.92,
      alpha: 0.16
    )
  )
  static let headerButtonActiveBorder = color(
    from: NSColor(
      srgbRed: 0.13,
      green: 0.46,
      blue: 0.92,
      alpha: 0.24
    )
  )
  static let dropOverlayBackground = color(
    from: NSColor(
      srgbRed: 0.93,
      green: 0.97,
      blue: 1.0,
      alpha: 1
    )
  )
  static let dropOverlayStroke = color(
    from: NSColor(
      srgbRed: 0.13,
      green: 0.46,
      blue: 0.92,
      alpha: 0.55
    )
  )
  static let dropOverlayAccent = color(
    from: NSColor(
      srgbRed: 0.18,
      green: 0.43,
      blue: 0.79,
      alpha: 1
    )
  )
  static let dropOverlayText = color(
    from: NSColor(
      srgbRed: 0.22,
      green: 0.39,
      blue: 0.62,
      alpha: 1
    )
  )
  static let dropOverlayHint = color(
    from: NSColor(
      srgbRed: 0.32,
      green: 0.46,
      blue: 0.61,
      alpha: 1
    )
  )

  static func color(from nsColor: NSColor) -> Color {
    Color(nsColor: nsColor)
  }
}
