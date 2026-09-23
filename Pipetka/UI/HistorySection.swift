import SwiftUI

struct HistorySection: View {
  @ObservedObject var store: PipetkaStore
  let onCopyText: (String) -> Void

  var body: some View {
    CardContainer {
      if store.history.isEmpty {
        Text("Use Pick or drop an image to capture colors.")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 4) {
            ForEach(store.history) { item in
              HistoryRowButton(
                item: item,
                format: store.format,
                cssColorSpace: store.cssColorSpace,
                action: {
                  onCopyText(
                    formatColor(
                      item,
                      format: store.format,
                      cssColorSpace: store.cssColorSpace
                    )
                  )
                }
              )
              .contextMenu {
                ForEach(ColorFormat.allCases, id: \.rawValue) { format in
                  Button("Copy as \(format.label(for: store.cssColorSpace))") {
                    onCopyText(
                      formatColor(
                        item,
                        format: format,
                        cssColorSpace: store.cssColorSpace
                      )
                    )
                  }
                }

                Divider()

                Button("Delete") {
                  store.removeHistoryItem(id: item.id)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(minHeight: 140, maxHeight: .infinity)
    .frame(maxWidth: .infinity)
    .layoutPriority(1)
  }
}

struct FooterBar: View {
  let historyCount: Int
  let isHistoryEmpty: Bool
  let showsRGBFormat: Bool
  let showsCSSProfile: Bool
  @Binding var format: ColorFormat
  @Binding var cssColorSpace: CSSColorSpace
  let onCopyHistory: (PaletteExportFormat) -> Void

  var body: some View {
    HStack(spacing: 10) {
      Text(historyCount == 1 ? "1 pick" : "\(historyCount) picks")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .fixedSize(horizontal: true, vertical: false)

      Spacer()

      if showsRGBFormat {
        RGBFormatPicker(selection: $format)
      }

      if showsCSSProfile {
        CSSProfilePicker(selection: $cssColorSpace)
      }

      MenuButton(
        title: "Copy history as...",
        controlSize: .small,
        isEnabled: !isHistoryEmpty,
        items: PaletteExportFormat.allCases.map { format in
          MenuButtonItem(title: format.label) {
            onCopyHistory(format)
          }
        }
      )
      .fixedSize()
    }
  }
}

struct DropOverlay: View {
  let isTargeted: Bool

  var body: some View {
    Group {
      if isTargeted {
        ZStack {
          RoundedRectangle(cornerRadius: 14)
            .fill(PlatformColor.dropOverlayBackground)

          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
              PlatformColor.dropOverlayStroke,
              style: StrokeStyle(lineWidth: 2, dash: [7, 6])
            )
            .padding(6)

          VStack(spacing: 6) {
            SymbolView(symbolName: "photo.on.rectangle.angled", fallbackText: "IMG")
              .foregroundColor(PlatformColor.dropOverlayAccent)

            Text("Drop images here to extract palettes")
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(PlatformColor.dropOverlayText)

            Text("We'll pull dominant colors into Imported Palettes")
              .font(.system(size: 11, weight: .medium))
              .foregroundColor(PlatformColor.dropOverlayHint)
          }
        }
        .padding(6)
      }
    }
  }
}
