import AppKit

// MARK: - Color Models

public struct NamedColorMatch {
  public let name: String
  public let matchedRed: Int
  public let matchedGreen: Int
  public let matchedBlue: Int
  public let distanceSquared: Int
  
  public init(name: String, matchedRed: Int, matchedGreen: Int, matchedBlue: Int, distanceSquared: Int) {
    self.name = name
    self.matchedRed = matchedRed
    self.matchedGreen = matchedGreen
    self.matchedBlue = matchedBlue
    self.distanceSquared = distanceSquared
  }
}

public struct PaletteColorBucket {
  public let color: NSColor
  public let pixelCount: Int

  public var rgbColor: NSColor { color.usingColorSpace(.extendedSRGB) ?? color }

  public var red: Int {
    ColorUtilities.byteComponent(ColorUtilities.extendedSRGBComponents(from: rgbColor)?.red ?? 0)
  }
  public var green: Int {
    ColorUtilities.byteComponent(ColorUtilities.extendedSRGBComponents(from: rgbColor)?.green ?? 0)
  }
  public var blue: Int {
    ColorUtilities.byteComponent(ColorUtilities.extendedSRGBComponents(from: rgbColor)?.blue ?? 0)
  }

  public var hex: String { ColorUtilities.hexString(from: rgbColor) }
  
  public init(color: NSColor, pixelCount: Int) {
    self.color = color
    self.pixelCount = pixelCount
  }
}
