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

          Text(historySubtitle(for: item))
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)

          gamutBadge

          if item.isHDR {
            Text("HDR")
              .font(.system(size: 10, weight: .semibold))
              .foregroundColor(.orange)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.orange.opacity(0.10), in: Capsule())
          }
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

  private var gamutBadge: some View {
    let isWideGamut = item.isWideGamut
    return Text(isWideGamut ? "P3" : "sRGB")
      .font(.system(size: 10, weight: .semibold))
      .foregroundColor(isWideGamut ? Color.accentColor : Color.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        isWideGamut ? Color.accentColor.opacity(0.10) : Color.black.opacity(0.05),
        in: Capsule()
      )
  }

  @ViewBuilder
  private var preview: some View {
    if item.hasExtendedColor {
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
    button.toolTip = "Copy \(accessibilityLabel)"
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

struct FormatPicker: View {
  @Binding var selection: ColorFormat
  @Binding var cssColorSpace: CSSColorSpace
  let formats: [ColorFormat]

  var body: some View {
    Group {
#if compiler(>=6.4)
      if #available(macOS 27.0, *) {
        Picker("Output", selection: tabSelection) {
          pickerOptions
        }
        .pickerStyle(.tabs)
      } else {
        Picker("Output", selection: tabSelection) {
          pickerOptions
        }
        .pickerStyle(.segmented)
      }
#else
      Picker("Output", selection: tabSelection) {
        pickerOptions
      }
      .pickerStyle(.segmented)
#endif
    }
    .labelsHidden()
    .formatPickerControlSize()
    .frame(maxWidth: .infinity, minHeight: 40)
    .accessibilityLabel("Color output")
  }

  private var tabSelection: Binding<ColorFormat> {
    Binding(
      get: { selection == .rgb ? .hex : selection },
      set: { selection = $0 }
    )
  }

  @ViewBuilder
  private var pickerOptions: some View {
    ForEach(formats, id: \.rawValue) { format in
      Text(format.label(for: cssColorSpace)).tag(format)
    }
  }
}

struct RGBFormatPicker: View {
  @Binding var selection: ColorFormat

  var body: some View {
    Picker(selection: $selection) {
      Text("HEX").tag(ColorFormat.hex)
      Text("RGB").tag(ColorFormat.rgb)
    } label: {
      Text(selection == .rgb ? "RGB" : "HEX")
    }
    .pickerStyle(.menu)
    .labelsHidden()
    .controlSize(.small)
    .fixedSize()
    .help("Choose HEX or RGB output")
    .accessibilityLabel("HEX or RGB output")
  }
}

private extension View {
  @ViewBuilder
  func formatPickerControlSize() -> some View {
    if #available(macOS 14.0, *) {
      controlSize(.extraLarge)
    } else {
      controlSize(.large)
    }
  }
}

struct CSSProfilePicker: View {
  @Binding var selection: CSSColorSpace

  var body: some View {
    Picker(selection: $selection) {
      pickerOptions
    } label: {
      Text(selection.tabLabel)
    }
    .pickerStyle(.menu)
    .labelsHidden()
    .controlSize(.small)
    .fixedSize()
    .help("Choose CSS \(selection.label) color space")
    .accessibilityLabel("CSS profile: \(selection.label)")
  }

  @ViewBuilder
  private var pickerOptions: some View {
    ForEach(CSSColorSpace.allCases) { colorSpace in
      Text(colorSpace.tabLabel)
        .tag(colorSpace)
        .help("Use CSS " + colorSpace.label)
    }
  }
}
