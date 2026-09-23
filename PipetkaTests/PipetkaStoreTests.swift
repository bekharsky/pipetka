import Cocoa
import XCTest
@testable import Pipetka

final class PipetkaStoreTests: XCTestCase {

  func testDefaultOutputIsCSSHDRWithOKLCH() {
    let store = PipetkaStore()

    XCTAssertEqual(store.format, .extendedRGB)
    XCTAssertEqual(store.cssColorSpace, .oklch)
  }

  private func makeColor(red: Int, green: Int, blue: Int) -> NSColor {
    NSColor(
      srgbRed: CGFloat(red) / 255,
      green: CGFloat(green) / 255,
      blue: CGFloat(blue) / 255,
      alpha: 1
    )
  }

  private func addPick(_ store: PipetkaStore, red: Int, green: Int, blue: Int) {
    store.addPick(red: red, green: green, blue: blue, previewPng: nil)
  }

  func testAddPaletteShowsImportedPaletteAndAddsColorsToHistory() {
    let store = PipetkaStore()

    store.addPalette(
      colors: [
        makeColor(red: 255, green: 0, blue: 0),
        makeColor(red: 0, green: 255, blue: 0)
      ],
      previewImage: nil
    )

    XCTAssertTrue(store.hasVisibleImportedPalettes)
    XCTAssertEqual(store.importedPalettes.count, 1)
    XCTAssertEqual(store.currentImportedPaletteIndex, 0)
    XCTAssertEqual(store.currentImportedPalette?.colors.count, 2)
    XCTAssertEqual(store.history.count, 2)
    XCTAssertEqual(formatColor(store.history[0], format: .hex), "#FF0000")
    XCTAssertEqual(formatColor(store.history[1], format: .hex), "#00FF00")
  }

  func testRemoveCurrentImportedPaletteClearsImportedPaletteStateButKeepsHistory() {
    let store = PipetkaStore()

    store.addPalette(
      colors: [makeColor(red: 255, green: 0, blue: 0)],
      previewImage: nil
    )
    store.removeCurrentImportedPalette()

    XCTAssertFalse(store.hasVisibleImportedPalettes)
    XCTAssertEqual(store.importedPalettes.count, 0)
    XCTAssertEqual(store.currentImportedPaletteIndex, 0)
    XCTAssertEqual(store.history.count, 1)
  }

  func testShowImportedPaletteSelectsRequestedPalette() {
    let store = PipetkaStore()

    store.addPalette(colors: [makeColor(red: 17, green: 34, blue: 51)], previewImage: nil)
    store.addPalette(colors: [makeColor(red: 68, green: 85, blue: 102)], previewImage: nil)

    store.showImportedPalette(at: 1)

    XCTAssertEqual(store.currentImportedPaletteIndex, 1)
    XCTAssertEqual(
      formatColor(store.currentImportedPalette!.colors[0], format: .hex),
      "#112233"
    )
  }

  func testCurrentRecentPickItemsUsesCurrentFormatAndIsLimitedToTen() {
    let store = PipetkaStore()

    for value in 0..<12 {
      addPick(store, red: value, green: value, blue: value)
    }

    store.format = .rgb
    let items = store.currentRecentPickItems()

    XCTAssertEqual(items.count, 10)
    XCTAssertTrue(items.allSatisfy { $0.text.contains("rgb(") })
    XCTAssertTrue(items.first?.text.contains("rgb(11, 11, 11)") == true)
  }

  func testFormatChangePublishesRecentPickItemsInUpdatedFormat() {
    let store = PipetkaStore()
    var publishedItems: [RecentPickMenuItem] = []
    store.onRecentPicksChanged = { publishedItems = $0 }

    addPick(store, red: 255, green: 128, blue: 0)
    store.format = .swiftUI

    XCTAssertEqual(publishedItems.count, 1)
    XCTAssertTrue(
      publishedItems[0].text.contains("Color(red: 1.000, green: 0.502, blue: 0.000)")
    )
  }

  func testClearAllResetsHistoryAndImportedPalettes() {
    let store = PipetkaStore()

    addPick(store, red: 1, green: 2, blue: 3)
    store.addPalette(colors: [makeColor(red: 10, green: 20, blue: 30)], previewImage: nil)

    store.clearAll()

    XCTAssertTrue(store.history.isEmpty)
    XCTAssertTrue(store.importedPalettes.isEmpty)
    XCTAssertFalse(store.hasVisibleImportedPalettes)
    XCTAssertEqual(store.currentImportedPaletteIndex, 0)
  }
}
