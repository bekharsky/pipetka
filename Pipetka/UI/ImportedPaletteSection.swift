import AppKit
import PipetkaCore
import SwiftUI

struct ImportedPaletteSection: View {
  @ObservedObject var store: PipetkaStore
  let palette: ImportedPalette
  let onCopyText: (String) -> Void
  @State private var burst: SwatchBurst?

  var body: some View {
    CardContainer(contentPadding: 9) {
      ZStack {
        HStack(alignment: .top, spacing: 12) {
          PreviewImageView(image: palette.previewImage, width: 84, height: 84)

          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
              if store.importedPalettes.count > 1 {
                HStack(spacing: 4) {
                  PagerButton(
                    symbolName: "chevron.left",
                    fallbackText: "<",
                    toolTip: "Previous imported palette",
                    action: {
                      store.showImportedPalette(at: store.currentImportedPaletteIndex - 1)
                    }
                  )
                  .disabled(store.currentImportedPaletteIndex == 0)

                  Text("\(store.currentImportedPaletteIndex + 1) of \(store.importedPalettes.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 42)

                  PagerButton(
                    symbolName: "chevron.right",
                    fallbackText: ">",
                    toolTip: "Next imported palette",
                    action: {
                      store.showImportedPalette(at: store.currentImportedPaletteIndex + 1)
                    }
                  )
                  .disabled(store.currentImportedPaletteIndex >= store.importedPalettes.count - 1)
                }
              }

              Spacer(minLength: 0)

              MenuButton(
                title: "Copy palette as...",
                controlSize: .small,
                items: PaletteExportFormat.allCases.map { format in
                  MenuButtonItem(title: format.label) {
                    onCopyText(exportColors(palette.colors, format: format))
                  }
                }
              )
              .fixedSize()

              SmallIconButton(
                symbolName: "trash",
                fallbackText: "Del",
                toolTip: "Remove imported palette",
                action: { store.removeCurrentImportedPalette() }
              )
              .padding(.trailing, 2)
            }
            .padding(.trailing, 2)

            if let sourceName = palette.sourceName, !sourceName.isEmpty {
              Text(sourceName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 4)
            }

            Spacer(minLength: 0)

            ScrollView(.horizontal, showsIndicators: true) {
              HStack(spacing: 8) {
                ForEach(palette.colors) { item in
                  PaletteSwatchChip(
                    color: item.displayColor,
                    toolTip: swatchToolTip(for: item),
                    onBurst: showBurst(frame:color:),
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
                  }
                }
              }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
          }
          .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        }

        if let burst {
          RoundedRectangle(cornerRadius: 11)
            .fill(PlatformColor.color(from: burst.color))
            .frame(width: 32, height: 32)
            .overlay(
              RoundedRectangle(cornerRadius: 11)
                .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
            .opacity(burst.isLifted ? 0 : 1)
            .position(
              x: burst.frame.midX,
              y: burst.frame.midY + (burst.isLifted ? -28 : 0)
            )
            .allowsHitTesting(false)
            .zIndex(2)
        }
      }
      .coordinateSpace(name: "ImportedPaletteSection")
      .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func showBurst(frame: CGRect, color: NSColor) {
    let id = UUID()
    burst = SwatchBurst(id: id, frame: frame, color: color, isLifted: false)

    DispatchQueue.main.async {
      guard burst?.id == id else { return }
      withAnimation(.easeOut(duration: 0.50)) {
        burst?.isLifted = true
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
      guard burst?.id == id else { return }
      burst = nil
    }
  }
}

struct SwatchBurst: Identifiable {
  let id: UUID
  let frame: CGRect
  let color: NSColor
  var isLifted: Bool
}

func swatchToolTip(for item: PickedColor) -> String {
  let match = NamedColorLookup.nearestMatch(red: item.red, green: item.green, blue: item.blue)
  let value = item.isExtendedRange
    ? formatColor(item, format: .extendedRGB)
    : formatColor(item, format: .hex)
  return "\(match.name)\n\(value)"
}

struct PreviewImageView: View {
  let image: NSImage?
  let width: CGFloat
  let height: CGFloat

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: width, height: height)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .stroke(Color.black.opacity(0.08), lineWidth: 1)
          )
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(PlatformColor.previewPlaceholder)
          .frame(width: width, height: height)
      }
    }
  }
}
