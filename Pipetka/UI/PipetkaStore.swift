import AppKit
import PipetkaCore
import SwiftUI

final class PipetkaStore: ObservableObject {
  @Published var history: [PickedColor] = []
  @Published var importedPalettes: [ImportedPalette] = []
  @Published var currentImportedPaletteIndex = 0
  @Published var isImportedPaletteVisible = false
  @Published var format: ColorFormat = .hex {
    didSet { publishRecentPickItems() }
  }
  @Published var cssColorSpace: CSSColorSpace = .sRGB {
    didSet { publishRecentPickItems() }
  }
  @Published var alwaysOnTop = false

  var onPickRequested: (() -> Void)?
  var onImportRequested: (() -> Void)?
  var onAlwaysOnTopToggleRequested: (() -> Void)?
  var onRecentPicksChanged: (([RecentPickMenuItem]) -> Void)?

  var hasVisibleImportedPalettes: Bool {
    !importedPalettes.isEmpty && isImportedPaletteVisible
  }

  var currentImportedPalette: ImportedPalette? {
    guard importedPalettes.indices.contains(currentImportedPaletteIndex) else {
      return nil
    }
    return importedPalettes[currentImportedPaletteIndex]
  }

  func requestPick() {
    onPickRequested?()
  }

  func requestImport() {
    onImportRequested?()
  }

  func requestAlwaysOnTopToggle() {
    onAlwaysOnTopToggleRequested?()
  }

  func setAlwaysOnTop(_ value: Bool) {
    alwaysOnTop = value
  }

  func addPick(red: Int, green: Int, blue: Int, previewPng: Data?) {
    addPick(
      color: NSColor(
        srgbRed: CGFloat(red) / 255,
        green: CGFloat(green) / 255,
        blue: CGFloat(blue) / 255,
        alpha: 1
      ),
      previewPng: previewPng
    )
  }

  func addPick(color: NSColor, previewPng: Data?) {
    let item = PickedColor(
      color: color,
      previewImage: previewPng.flatMap(NSImage.init(data:)),
      pickedAt: Date()
    )
    history.insert(item, at: 0)
    publishRecentPickItems()
  }

  func addPalette(colors: [NSColor], previewImage: NSImage?, sourceName: String? = nil) {
    let items = colors.map {
      PickedColor(
        color: $0,
        previewImage: nil,
        pickedAt: Date()
      )
    }

    importedPalettes.insert(
      ImportedPalette(
        colors: items,
        previewImage: previewImage,
        sourceName: sourceName,
        importedAt: Date()
      ),
      at: 0
    )
    currentImportedPaletteIndex = 0
    isImportedPaletteVisible = true
    history.insert(contentsOf: items, at: 0)
    publishRecentPickItems()
  }

  func importSelectedItems(at urls: [URL], includesNestedFolders: Bool) {
    importImages(loadImportableImages(from: urls, includesNestedFolders: includesNestedFolders))
  }

  func removeCurrentImportedPalette() {
    guard importedPalettes.indices.contains(currentImportedPaletteIndex) else {
      clearImportedPalettes()
      return
    }

    importedPalettes.remove(at: currentImportedPaletteIndex)
    if importedPalettes.isEmpty {
      clearImportedPalettes()
    } else {
      currentImportedPaletteIndex = min(currentImportedPaletteIndex, importedPalettes.count - 1)
      isImportedPaletteVisible = true
    }
  }

  func showImportedPalette(at index: Int) {
    guard importedPalettes.indices.contains(index) else {
      return
    }

    currentImportedPaletteIndex = index
    isImportedPaletteVisible = true
  }

  func removeHistoryItem(id: PickedColor.ID) {
    history.removeAll { $0.id == id }
    publishRecentPickItems()
  }

  func clearAll() {
    history.removeAll()
    clearImportedPalettes()
    publishRecentPickItems()
  }

  func currentRecentPickItems() -> [RecentPickMenuItem] {
    Array(history.prefix(10)).map {
      RecentPickMenuItem(
        text: recentPickMenuText(
          for: $0,
          format: format,
          cssColorSpace: cssColorSpace
        ),
        color: $0.previewColor
      )
    }
  }

  private func clearImportedPalettes() {
    importedPalettes.removeAll()
    currentImportedPaletteIndex = 0
    isImportedPaletteVisible = false
  }

  private func importImages(_ images: [(url: URL, image: NSImage)]) {
    guard !images.isEmpty else {
      return
    }

    for entry in images.reversed() {
      let colors = ImagePaletteExtractor.extractPalette(from: entry.image).map(\.color)
      guard !colors.isEmpty else {
        continue
      }
      addPalette(
        colors: colors,
        previewImage: entry.image,
        sourceName: entry.url.lastPathComponent
      )
    }
  }

  private func loadImportableImages(from urls: [URL], includesNestedFolders: Bool) -> [(url: URL, image: NSImage)] {
    expandedImportURLs(from: urls, includesNestedFolders: includesNestedFolders).compactMap { url in
      guard let image = NSImage(contentsOf: url) else {
        return nil
      }
      return (url: url, image: image)
    }
  }

  private func expandedImportURLs(from urls: [URL], includesNestedFolders: Bool) -> [URL] {
    var collectedFiles: [URL] = []
    let fileManager = FileManager.default

    for url in urls {
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        continue
      }

      if isDirectory.boolValue {
        if includesNestedFolders {
          let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
          )

          while let fileURL = enumerator?.nextObject() as? URL {
            if isImportableImageURL(fileURL) {
              collectedFiles.append(fileURL)
            }
          }
        } else if let children = try? fileManager.contentsOfDirectory(
          at: url,
          includingPropertiesForKeys: [.isRegularFileKey],
          options: [.skipsHiddenFiles]
        ) {
          collectedFiles.append(contentsOf: children.filter(isImportableImageURL(_:)))
        }
      } else if isImportableImageURL(url) {
        collectedFiles.append(url)
      }
    }

    return collectedFiles
  }

  private func isImportableImageURL(_ url: URL) -> Bool {
    let pathExtension = url.pathExtension.lowercased()
    return ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic", "heif"].contains(pathExtension)
  }

  private func publishRecentPickItems() {
    onRecentPicksChanged?(currentRecentPickItems())
  }
}
