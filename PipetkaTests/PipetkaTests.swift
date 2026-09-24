import Cocoa
import XCTest
@testable import PipetkaCore
@testable import Pipetka

class PipetkaTests: XCTestCase {

  private func makePickedColor(red: Int, green: Int, blue: Int) -> PickedColor {
    PickedColor(
      color: NSColor(
        srgbRed: CGFloat(red) / 255,
        green: CGFloat(green) / 255,
        blue: CGFloat(blue) / 255,
        alpha: 1
      ),
      previewImage: nil,
      pickedAt: Date(timeIntervalSince1970: 0)
    )
  }

  private func makeImage(
    width: Int,
    height: Int,
    pixels: [(Int, Int, Int, Int)]
  ) -> NSImage {
    let bytesPerRow = width * 4
    var data = pixels.flatMap { pixel in
      [UInt8(pixel.0), UInt8(pixel.1), UInt8(pixel.2), UInt8(pixel.3)]
    }

    let bitmap = data.withUnsafeMutableBytes { bytes -> NSBitmapImageRep in
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: bytesPerRow,
        bitsPerPixel: 32
      )!
    }

    memcpy(bitmap.bitmapData, data, data.count)

    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(bitmap)
    return image
  }

  private func hexString(for color: NSColor) -> String {
    let rgb = color.usingColorSpace(.deviceRGB) ?? color
    return String(
      format: "#%02X%02X%02X",
      Int(round(rgb.redComponent * 255)),
      Int(round(rgb.greenComponent * 255)),
      Int(round(rgb.blueComponent * 255))
    )
  }

  func testFormatColorHexRgbAndSwiftUIOutputs() {
    let item = makePickedColor(red: 255, green: 128, blue: 0)

    XCTAssertEqual(formatColor(item, format: .hex), "#FF8000")
    XCTAssertEqual(formatColor(item, format: .rgb), "rgb(255, 128, 0)")
    XCTAssertTrue(
      formatColor(item, format: .extendedRGB, cssColorSpace: .oklch).hasPrefix("oklch(")
    )
    XCTAssertEqual(
      formatColor(item, format: .swiftUI),
      "Color(red: 1.000, green: 0.502, blue: 0.000)"
    )
  }

  func testOKLCHPreservesExtendedHDRValuesWithoutNaN() {
    let color = NSColor(
      colorSpace: .extendedSRGB,
      components: [1.6369, -0.5836, 1.3915, 1],
      count: 4
    )
    let item = PickedColor(color: color, previewImage: nil, pickedAt: Date(timeIntervalSince1970: 0))

    let value = formatColor(item, format: .extendedRGB, cssColorSpace: .oklch)

    XCTAssertTrue(value.hasPrefix("oklch("))
    XCTAssertFalse(value.contains("nan"))
    XCTAssertFalse(value.contains("NaN"))
  }

  func testFormatColorHslOutputForOrange() {
    let item = makePickedColor(red: 255, green: 128, blue: 0)

    XCTAssertEqual(formatColor(item, format: .hsl), "hsl(30 100% 50%)")
  }

  func testFormatHslOutputForGrayHasZeroSaturation() {
    let item = makePickedColor(red: 128, green: 128, blue: 128)

    XCTAssertEqual(formatHsl(item), "hsl(0 0% 50%)")
  }

  func testExtendedRGBFormatPreservesHDRComponents() {
    let color = NSColor(
      colorSpace: .extendedSRGB,
      components: [1.25, 0.5, 0.25, 1],
      count: 4
    )
    let item = PickedColor(color: color, previewImage: nil, pickedAt: Date(timeIntervalSince1970: 0))

    XCTAssertTrue(item.isHDR)
    XCTAssertEqual(formatColor(item, format: .extendedRGB), "color(srgb 1.2500 0.5000 0.2500)")
    XCTAssertTrue(formatColor(item, format: .hex).hasPrefix("#"))
    XCTAssertFalse(formatColor(item, format: .hex).contains("See"))
    XCTAssertTrue(formatColor(item, format: .rgb).hasPrefix("rgb("))
    XCTAssertFalse(formatColor(item, format: .rgb).contains("See"))
    XCTAssertTrue(formatColor(item, format: .hsl).hasPrefix("hsl("))
    XCTAssertFalse(formatColor(item, format: .hsl).contains("See"))
    XCTAssertEqual(
      formatColor(item, format: .swiftUI),
      "Color(nsColor: NSColor(colorSpace: .extendedSRGB, components: [1.250, 0.500, 0.250, 1.000], count: 4))"
    )
    XCTAssertTrue(displayFormatColor(item, format: .swiftUI).contains("\n"))
  }

  func testCSSHDRCanUseDisplayP3() {
    guard
      let cgColorSpace = CGColorSpace(name: CGColorSpace.extendedDisplayP3),
      let cgColor = CGColor(
        colorSpace: cgColorSpace,
        components: [1.25, 0.5, 0.25, 1]
      ),
      let color = NSColor(cgColor: cgColor)
    else {
      XCTFail("Extended Display P3 is unavailable")
      return
    }

    let item = PickedColor(color: color, previewImage: nil, pickedAt: Date(timeIntervalSince1970: 0))

    XCTAssertEqual(
      formatColor(item, format: .extendedRGB, cssColorSpace: .displayP3),
      "color(display-p3 1.2500 0.5000 0.2500)"
    )
  }

  func testCSSProfilesUseTheirOwnEncodings() {
    let color = NSColor(
      colorSpace: .extendedSRGB,
      components: [1.25, 0.5, 0.25, 1],
      count: 4
    )
    let item = PickedColor(color: color, previewImage: nil, pickedAt: Date(timeIntervalSince1970: 0))

    XCTAssertTrue(formatColor(item, format: .extendedRGB, cssColorSpace: .rec2020).hasPrefix("color(rec2020 "))
    XCTAssertTrue(formatColor(item, format: .extendedRGB, cssColorSpace: .rec2100Linear).hasPrefix("color(rec2100-linear "))
    XCTAssertTrue(formatColor(item, format: .extendedRGB, cssColorSpace: .rec2100PQ).hasPrefix("color(rec2100-pq "))
    XCTAssertTrue(formatColor(item, format: .extendedRGB, cssColorSpace: .rec2100HLG).hasPrefix("color(rec2100-hlg "))
  }

  func testHDRDisplayColorToneMapsIntoSDRWithoutChangingExportComponents() {
    let color = NSColor(
      colorSpace: .extendedSRGB,
      components: [0, 35.0312, 25.6562, 1],
      count: 4
    )
    let display = ColorUtilities.displayColor(from: color).usingColorSpace(.deviceRGB)!

    XCTAssertGreaterThanOrEqual(display.redComponent, 0)
    XCTAssertGreaterThanOrEqual(display.greenComponent, 0)
    XCTAssertGreaterThanOrEqual(display.blueComponent, 0)
    XCTAssertLessThanOrEqual(display.redComponent, 1)
    XCTAssertLessThanOrEqual(display.greenComponent, 1)
    XCTAssertLessThanOrEqual(display.blueComponent, 1)
    XCTAssertEqual(
      ColorUtilities.cssExtendedSRGBString(from: color),
      "color(srgb 0.0000 35.0312 25.6562)"
    )
  }

  func testWideGamutFormatsDoNotMislabelNegativeSRGBChannelsAsHDR() {
    let color = NSColor(
      colorSpace: .extendedSRGB,
      components: [0, -40.0938, 0, 1],
      count: 4
    )
    let item = PickedColor(color: color, previewImage: nil, pickedAt: Date(timeIntervalSince1970: 0))

    XCTAssertFalse(item.isHDR)
    XCTAssertTrue(item.isWideGamut)
    XCTAssertEqual(formatColor(item, format: .hex), "#000000")
    XCTAssertEqual(namedColorName(for: item), "Black")
    XCTAssertEqual(historySubtitle(for: item), namedColorName(for: item))
  }

  func testHDRHalfFloatDecoderPreservesExtendedValuesAndRejectsNaN() {
    XCTAssertEqual(HDRColorDecoder.float(fromHalfBits: 0x3C00), 1, accuracy: 0.0001)
    XCTAssertEqual(HDRColorDecoder.float(fromHalfBits: 0x3800), 0.5, accuracy: 0.0001)
    XCTAssertEqual(HDRColorDecoder.float(fromHalfBits: 0x4000), 2, accuracy: 0.0001)
    XCTAssertTrue(HDRColorDecoder.float(fromHalfBits: 0x7E00).isNaN)

    var pixel: [UInt8] = [
      0x00, 0x3C, // 1.0
      0x00, 0x38, // 0.5
      0x00, 0x40, // 2.0
      0x00, 0x3C  // 1.0 alpha
    ]
    let components = pixel.withUnsafeMutableBufferPointer { buffer in
      (0..<4).compactMap { index in
        HDRColorDecoder.component(in: buffer.baseAddress!, at: index * 2)
      }
    }
    XCTAssertEqual(components, [1, 0.5, 2, 1])

    pixel[2] = 0x00
    pixel[3] = 0x7E
    let rejected = pixel.withUnsafeBufferPointer {
      HDRColorDecoder.component(in: $0.baseAddress!, at: 2)
    }
    XCTAssertNil(rejected)
  }

  func testLensFrameUsesPreferredPlacementWhenSpaceAllows() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let mousePoint = CGPoint(x: 300, y: 600)

    let frame = PickerLensView.frameForLens(around: mousePoint, visibleFrame: visibleFrame)

    XCTAssertEqual(frame, CGRect(x: 326, y: 366, width: 184, height: 216))
  }

  func testLensFrameFlipsAndClampsNearScreenEdges() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 400, height: 300)
    let mousePoint = CGPoint(x: 390, y: 10)

    let frame = PickerLensView.frameForLens(around: mousePoint, visibleFrame: visibleFrame)

    XCTAssertEqual(frame, CGRect(x: 180, y: 28, width: 184, height: 216))
  }

  func testImagePaletteExtractorReturnsDominantColors() {
    let image = makeImage(
      width: 4,
      height: 2,
      pixels: [
        (255, 0, 0, 255), (255, 0, 0, 255), (255, 0, 0, 255), (0, 255, 0, 255),
        (255, 0, 0, 255), (0, 0, 255, 255), (0, 255, 0, 255), (0, 255, 0, 255)
      ]
    )

    let palette = ImagePaletteExtractor.extractPalette(from: image, maxColors: 3)

    XCTAssertEqual(palette.count, 3)
    XCTAssertEqual(
      palette.map { hexString(for: $0.color) },
      ["#FF0000", "#00FF00", "#0000FF"]
    )
  }

  func testImagePaletteExtractorIgnoresFullyTransparentPixels() {
    let image = makeImage(
      width: 2,
      height: 2,
      pixels: [
        (0, 0, 0, 0), (0, 0, 0, 0),
        (255, 128, 0, 255), (255, 128, 0, 255)
      ]
    )

    let palette = ImagePaletteExtractor.extractPalette(from: image, maxColors: 3)

    XCTAssertEqual(palette.count, 1)
    let color = palette[0].color.usingColorSpace(.deviceRGB) ?? palette[0].color
    XCTAssertEqual(Int(round(color.redComponent * 255)), 255)
    XCTAssertEqual(Int(round(color.greenComponent * 255)), 128)
    XCTAssertEqual(Int(round(color.blueComponent * 255)), 0)
  }

}
