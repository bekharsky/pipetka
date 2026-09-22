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
        GeometryReader { proxy in
          ScrollView {
            VStack(spacing: 4) {
              ForEach(store.history) { item in
                HistoryRowButton(
                  item: item,
                  format: store.format,
                  action: {
                    onCopyText(formatColor(item, format: store.format))
                  }
                )
                .contextMenu {
                  ForEach(ColorFormat.allCases, id: \.rawValue) { format in
                    Button("Copy as \(format.label)") {
                      onCopyText(formatColor(item, format: format))
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
            .frame(width: proxy.size.width, alignment: .leading)
          }
          .frame(width: proxy.size.width)
        }
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
  let onCopyHistory: (PaletteExportFormat) -> Void
  let onClearHistory: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Text(historyCount == 1 ? "1 pick" : "\(historyCount) picks")
        .font(.system(size: 11))
        .foregroundColor(.secondary)

      Spacer()

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

      NativeButton(
        title: "Clear History",
        controlSize: .small,
        isEnabled: !isHistoryEmpty,
        action: onClearHistory
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
