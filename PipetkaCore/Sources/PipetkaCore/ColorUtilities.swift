import Cocoa

public struct ExtendedSRGBComponents: Equatable {
  public let red: CGFloat
  public let green: CGFloat
  public let blue: CGFloat
  public let alpha: CGFloat

  public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }
}

public enum ColorUtilities {
  /// Returns color components in extended sRGB without clipping values outside 0...1.
  public static func extendedSRGBComponents(from color: NSColor) -> ExtendedSRGBComponents? {
    guard let extendedColor = color.usingColorSpace(.extendedSRGB) else {
      return nil
    }

    return ExtendedSRGBComponents(
      red: sanitizedComponent(extendedColor.redComponent),
      green: sanitizedComponent(extendedColor.greenComponent),
      blue: sanitizedComponent(extendedColor.blueComponent),
      alpha: sanitizedComponent(extendedColor.alphaComponent)
    )
  }

  private static func sanitizedComponent(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else {
      return value.isNaN || value < 0 ? 0 : 1
    }
    return value
  }

  public static func isExtendedRange(_ components: ExtendedSRGBComponents) -> Bool {
    let tolerance: CGFloat = 0.0001
    return [components.red, components.green, components.blue].contains {
      !$0.isFinite || $0 < -tolerance || $0 > 1 + tolerance
    }
  }

  public static func clampedUnit(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else {
      return value.isNaN || value < 0 ? 0 : 1
    }
    return min(max(value, 0), 1)
  }

  public static func byteComponent(_ value: CGFloat) -> Int {
    Int(round(clampedUnit(value) * 255))
  }

  public static func hexString(from color: NSColor) -> String {
    guard let components = extendedSRGBComponents(from: color) else {
      return "#000000"
    }

    return String(
      format: "#%02X%02X%02X",
      byteComponent(components.red),
      byteComponent(components.green),
      byteComponent(components.blue)
    )
  }

  /// Returns a CSS Color 4 value that keeps extended sRGB components intact.
  public static func cssExtendedSRGBString(
    from color: NSColor,
    precision: Int = 4
  ) -> String {
    guard let components = extendedSRGBComponents(from: color) else {
      return "color(srgb 0 0 0)"
    }

    let format = "color(srgb %0.*f %0.*f %0.*f)"
    return String(
      format: format,
      precision, Double(components.red),
      precision, Double(components.green),
      precision, Double(components.blue)
    )
  }

  /// Returns an SDR display color while preserving the hue of extended-range values.
  /// The original extended components remain available for export and copying.
  public static func displayColor(from color: NSColor) -> NSColor {
    guard let components = extendedSRGBComponents(from: color) else {
      return color
    }

    let peak = max(1, max(components.red, max(components.green, components.blue)))
    let mapped: (CGFloat) -> CGFloat = { value in
      clampedUnit(max(value, 0) / peak)
    }

    return NSColor(
      srgbRed: mapped(components.red),
      green: mapped(components.green),
      blue: mapped(components.blue),
      alpha: clampedUnit(components.alpha)
    )
  }

  /// Converts RGB (0-255) to HSL (h: 0-360, s: 0-100, l: 0-100)
  public static func rgbToHsl(r: Int, g: Int, b: Int) -> (h: Int, s: Int, l: Int) {
    let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
    let cMax = max(rf, gf, bf), cMin = min(rf, gf, bf)
    let l = (cMax + cMin) / 2
    guard cMax != cMin else { return (0, 0, Int(round(l * 100))) }
    let d = cMax - cMin
    let s = l > 0.5 ? d / (2 - cMax - cMin) : d / (cMax + cMin)
    var h: Double
    switch cMax {
    case rf: h = (gf - bf) / d + (gf < bf ? 6 : 0)
    case gf: h = (bf - rf) / d + 2
    default:  h = (rf - gf) / d + 4
    }
    return (Int(round(h / 6 * 360)), Int(round(s * 100)), Int(round(l * 100)))
  }
}
