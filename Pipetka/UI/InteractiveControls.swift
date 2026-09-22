import AppKit
import SwiftUI

struct HistoryRowButton: View {
  let item: PickedColor
  let format: ColorFormat
  let cssColorSpace: CSSColorSpace
  let action: () -> Void

  @State private var isHovering = false
  @State private var showBurst = false
  @State private var burstLifted = false
  @State private var burstID = 0
  @FocusState private var isFocused: Bool

  var body: some View {
    ZStack(alignment: .trailing) {
      rowContent

      HistoryRowControl(
        accessibilityLabel: formatColor(
          item,
          format: format,
          cssColorSpace: cssColorSpace
        ),
        onActivate: {
          triggerBurst()
          action()
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .focusable()
      .focused($isFocused)
      .disablesSystemFocusEffectWhenAvailable()

      if isFocused {
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.accentColor.opacity(0.045))
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(Color.accentColor.opacity(0.58), lineWidth: 1.5)
          )
          .padding(1)
          .allowsHitTesting(false)
      }

      if showBurst {
        SymbolView(symbolName: "doc.on.doc", fallbackText: "Copy")
          .foregroundColor(.secondary)
          .opacity(burstLifted ? 0 : 1)
          .offset(x: -6, y: burstLifted ? -22 : -6)
          .zIndex(1)
      }
    }
    .accessibilityLabel(
      formatColor(item, format: format, cssColorSpace: cssColorSpace)
    )
    .accessibilityHint("Copies this color to the clipboard")
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.12)) {
        isHovering = hovering
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var rowContent: some View {
    HStack(alignment: .top, spacing: 10) {
      preview

      VStack(alignment: .leading, spacing: 4) {
        Text(
          displayFormatColor(
            item,
            format: format,
            cssColorSpace: cssColorSpace
          )
        )
          .font(.system(size: 13, weight: .semibold, design: .monospaced))
          .lineLimit(nil)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .layoutPriority(1)

        HStack(alignment: .top, spacing: 6) {
          RoundedRectangle(cornerRadius: 8)
            .fill(PlatformColor.color(from: item.previewColor))
            .frame(width: 16, height: 16)
            .overlay(
              RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )

          Text(
            historySubtitle(
              for: item,
              cssColorSpace: cssColorSpace
            )
          )
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(.trailing, 30)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(isHovering ? PlatformColor.rowHover : PlatformColor.rowBackground)
    .cornerRadius(12)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.black.opacity(0.05), lineWidth: 1)
    )
    .overlay(alignment: .trailing) {
      SymbolView(symbolName: "doc.on.doc", fallbackText: "Copy")
        .foregroundColor(.secondary)
        .opacity(isHovering ? 1 : 0)
        .padding(.trailing, 10)
        .allowsHitTesting(false)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var preview: some View {
    if item.isExtendedRange {
      RoundedRectangle(cornerRadius: 10)
        .fill(PlatformColor.color(from: item.previewColor))
        .frame(width: 46, height: 46)
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    } else if let previewImage = item.previewImage {
      Image(nsImage: previewImage)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    } else {
      RoundedRectangle(cornerRadius: 10)
        .fill(PlatformColor.color(from: item.previewColor))
        .frame(width: 46, height: 46)
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
  }

  private func triggerBurst() {
    burstID += 1
    let currentBurstID = burstID
    showBurst = true
    burstLifted = false

    DispatchQueue.main.async {
      guard burstID == currentBurstID else { return }
      withAnimation(.easeOut(duration: 0.32)) {
        burstLifted = true
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
      guard burstID == currentBurstID else { return }
      burstLifted = false
      showBurst = false
    }
  }
}

private struct HistoryRowControl: NSViewRepresentable {
  let accessibilityLabel: String
  let onActivate: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onActivate: onActivate)
  }

  func makeNSView(context: Context) -> FullRowButton {
    let button = FullRowButton()
    button.target = context.coordinator
    button.action = #selector(Coordinator.activate(_:))
    // The button is an invisible full-row hit target. Keeping the long code
    // string as its title makes AppKit use that string as the intrinsic width
    // and can push the visible SwiftUI text outside the card.
    button.title = ""
    button.setAccessibilityLabel(accessibilityLabel)
    button.toolTip = "Copy \(accessibilityLabel)"
    return button
  }

  func updateNSView(_ button: FullRowButton, context: Context) {
    context.coordinator.onActivate = onActivate
    button.title = ""
    button.setAccessibilityLabel(accessibilityLabel)
  }

  final class Coordinator: NSObject {
    var onActivate: () -> Void

    init(onActivate: @escaping () -> Void) {
      self.onActivate = onActivate
    }

    @objc
    func activate(_ sender: NSButton) {
      onActivate()
    }
  }
}

private final class FullRowButton: NSButton {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    focusRingType = .none
    refusesFirstResponder = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func draw(_ dirtyRect: NSRect) { }

}

private extension View {
  @ViewBuilder
  func disablesSystemFocusEffectWhenAvailable() -> some View {
    if #available(macOS 14.0, *) {
      focusEffectDisabled()
    } else {
      self
    }
  }
}

struct PaletteSwatchChip: View {
  let color: NSColor
  let toolTip: String
  let onBurst: (CGRect, NSColor) -> Void
  let action: () -> Void

  var body: some View {
    GeometryReader { proxy in
      Button {
        onBurst(proxy.frame(in: .named("ImportedPaletteSection")), color)
        action()
      } label: {
        swatch
      }
    }
    .frame(width: 32, height: 32)
    .buttonStyle(.plain)
    .help(toolTip)
    .accessibilityLabel(toolTip)
    .accessibilityHint("Copies this color to the clipboard")
  }

  private var swatch: some View {
    RoundedRectangle(cornerRadius: 11)
      .fill(PlatformColor.color(from: color))
      .frame(width: 32, height: 32)
      .overlay(
        RoundedRectangle(cornerRadius: 11)
          .stroke(Color.black.opacity(0.10), lineWidth: 1)
      )
  }
}

struct FormatPillControl: View {
  @Binding var selection: ColorFormat
  let formats: [ColorFormat]

  private let controlHeight: CGFloat = 34
  private let inset: CGFloat = 4
  private let spacing: CGFloat = 4
  private let activeHeight: CGFloat = 26
  private let activeCornerRadius: CGFloat = 9
  private let trackCornerRadius: CGFloat = 11

  var body: some View {
    GeometryReader { proxy in
      let activeWidth = segmentWidth(totalWidth: proxy.size.width)

      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: trackCornerRadius)
          .fill(Color.black.opacity(0.075))

        if let selectedIndex = formats.firstIndex(of: selection) {
          RoundedRectangle(cornerRadius: activeCornerRadius)
            .fill(PlatformColor.selectedSegmentBackground)
            .frame(width: activeWidth, height: activeHeight)
            .overlay(
              RoundedRectangle(cornerRadius: activeCornerRadius)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .offset(x: activeOffset(for: selectedIndex, width: activeWidth), y: inset)
        }

        HStack(spacing: spacing) {
          ForEach(formats, id: \.rawValue) { format in
            FormatSegmentButton(
              label: format.label,
              isSelected: selection == format,
              onActivate: {
                select(format)
              },
              onMove: { offset in
                selectAdjacentFormat(to: format, offset: offset)
              }
            )
            .frame(maxWidth: .infinity)
            .frame(height: activeHeight)
          }
        }
        .padding(inset)
      }
      .overlay(
        RoundedRectangle(cornerRadius: trackCornerRadius)
          .stroke(Color.black.opacity(0.06), lineWidth: 1)
      )
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Color format")
    }
    .frame(height: controlHeight)
  }

  private func segmentWidth(totalWidth: CGFloat) -> CGFloat {
    let availableWidth = totalWidth - (inset * 2) - (spacing * CGFloat(max(formats.count - 1, 0)))
    return max(0, availableWidth / CGFloat(max(formats.count, 1)))
  }

  private func activeOffset(for index: Int, width: CGFloat) -> CGFloat {
    inset + CGFloat(index) * (width + spacing)
  }

  private func selectAdjacentFormat(to format: ColorFormat, offset: Int) {
    guard let index = formats.firstIndex(of: format) else {
      return
    }

    let nextIndex = min(max(index + offset, 0), formats.count - 1)
    guard nextIndex != index else {
      return
    }

    select(formats[nextIndex])
  }

  private func select(_ format: ColorFormat) {
    withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
      selection = format
    }
  }
}

private struct FormatSegmentButton: NSViewRepresentable {
  let label: String
  let isSelected: Bool
  let onActivate: () -> Void
  let onMove: (Int) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onActivate: onActivate, onMove: onMove)
  }

  func makeNSView(context: Context) -> KeyboardSegmentButton {
    let button = KeyboardSegmentButton()
    button.target = context.coordinator
    button.action = #selector(Coordinator.activate(_:))
    button.title = label
    button.setAccessibilityLabel(label)
    button.toolTip = "Select \(label) color format"
    button.onMove = context.coordinator.onMove
    return button
  }

  func updateNSView(_ button: KeyboardSegmentButton, context: Context) {
    context.coordinator.onActivate = onActivate
    context.coordinator.onMove = onMove
    button.title = label
    button.setAccessibilityLabel(label)
    button.setAccessibilityValue(isSelected ? "Selected" : "Not selected")
    button.textColor = isSelected ? .labelColor : .secondaryLabelColor
    button.onMove = context.coordinator.onMove
  }

  final class Coordinator: NSObject {
    var onActivate: () -> Void
    var onMove: (Int) -> Void

    init(onActivate: @escaping () -> Void, onMove: @escaping (Int) -> Void) {
      self.onActivate = onActivate
      self.onMove = onMove
    }

    @objc
    func activate(_ sender: NSButton) {
      onActivate()
    }
  }
}

private final class KeyboardSegmentButton: NSButton {
  var onMove: ((Int) -> Void)?
  var textColor: NSColor = .secondaryLabelColor {
    didSet { needsDisplay = true }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    title = ""
    isBordered = false
    focusRingType = .default
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func draw(_ dirtyRect: NSRect) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.lineBreakMode = .byTruncatingTail

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
      .foregroundColor: textColor,
      .paragraphStyle: paragraphStyle
    ]
    let textRect = bounds.insetBy(dx: 2, dy: 4)
    title.draw(in: textRect, withAttributes: attributes)
  }

  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
  }

  override var focusRingMaskBounds: NSRect {
    bounds
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 123:
      moveFocus(by: -1)
    case 124:
      moveFocus(by: 1)
    case 36, 49, 76:
      performClick(nil)
    default:
      super.keyDown(with: event)
    }
  }

  private func moveFocus(by offset: Int) {
    let target = offset < 0 ? previousValidKeyView : nextValidKeyView
    guard let target = target as? KeyboardSegmentButton else {
      return
    }

    onMove?(offset)
    window?.makeFirstResponder(target)
  }
}
