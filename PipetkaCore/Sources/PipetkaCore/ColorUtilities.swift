import Cocoa

public struct ColorComponents: Equatable {
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

public typealias ExtendedSRGBComponents = ColorComponents

public enum ColorUtilities {
  /// The linear, extended Display P3 space used by ScreenCaptureKit's HDR screenshot preset.
  public static let extendedDisplayP3ColorSpace: NSColorSpace? = {
    guard let cgColorSpace = CGColorSpace(name: CGColorSpace.extendedDisplayP3) else {
      return nil
    }
    return NSColorSpace(cgColorSpace: cgColorSpace)
  }()

  /// Linear extended sRGB is used to test whether a color falls outside the sRGB gamut.
  private static let extendedLinearSRGBColorSpace: NSColorSpace? = {
    guard let cgColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else {
      return nil
    }
    return NSColorSpace(cgColorSpace: cgColorSpace)
  }()

  /// Returns color components in extended sRGB without clipping values outside 0...1.
  public static func extendedSRGBComponents(from color: NSColor) -> ExtendedSRGBComponents? {
    components(from: color, in: .extendedSRGB)
  }

  /// Returns color components in extended Display P3 without clipping values outside 0...1.
  public static func extendedDisplayP3Components(from color: NSColor) -> ColorComponents? {
    guard let extendedDisplayP3ColorSpace else {
      return nil
    }
    return components(from: color, in: extendedDisplayP3ColorSpace)
  }

  public static func components(
    from color: NSColor,
    in colorSpace: NSColorSpace
  ) -> ColorComponents? {
    guard let convertedColor = color.usingColorSpace(colorSpace) else {
      return nil
    }

    return ColorComponents(
      red: sanitizedComponent(convertedColor.redComponent),
      green: sanitizedComponent(convertedColor.greenComponent),
      blue: sanitizedComponent(convertedColor.blueComponent),
      alpha: sanitizedComponent(convertedColor.alphaComponent)
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

  /// True when the color contains component values above SDR reference white in
  /// the linear Display P3 space used by the screen-capture pipeline.
  /// Negative sRGB components alone do not indicate HDR; they usually indicate
  /// a color outside the sRGB gamut.
  public static func isHDR(_ color: NSColor) -> Bool {
    guard let components = extendedDisplayP3Components(from: color) else {
      return false
    }
    let tolerance: CGFloat = 0.001
    return [components.red, components.green, components.blue].contains {
      $0.isFinite && $0 > 1 + tolerance
    }
  }

  /// True when the color's chromaticity lies outside the sRGB gamut.
  /// Linear RGB conversion preserves the sign of out-of-gamut channels, while
  /// avoiding mistaking HDR brightness above 1 for a gamut difference.
  public static func isWideGamut(_ color: NSColor) -> Bool {
    guard let extendedLinearSRGBColorSpace,
          let components = components(from: color, in: extendedLinearSRGBColorSpace)
    else {
      return false
    }
    let tolerance: CGFloat = 0.001
    return [components.red, components.green, components.blue].contains {
      $0 < -tolerance
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
    cssColorString(
      from: color,
      in: .extendedSRGB,
      cssName: "srgb",
      precision: precision
    )
  }

  /// Returns an extended CSS Color 4 value in the requested color space.
  public static func cssColorString(
    from color: NSColor,
    in colorSpace: NSColorSpace,
    cssName: String,
    precision: Int = 4
  ) -> String {
    guard let components = components(from: color, in: colorSpace) else {
      return "color(\(cssName) 0 0 0)"
    }

    let format = "color(\(cssName) %0.*f %0.*f %0.*f)"
    return String(
      format: format,
      precision, Double(components.red),
      precision, Double(components.green),
      precision, Double(components.blue)
    )
  }

  /// Formats an extended sRGB color in the CSS Rec. 2020 color space.
  ///
  /// Rec. 2020 uses its own RGB primaries and transfer curve, so its
  /// components cannot be copied from an extended-sRGB NSColor directly.
  public static func cssRec2020String(
    from color: NSColor,
    precision: Int = 4
  ) -> String {
    guard let components = linearRec2020Components(from: color) else {
      return "color(rec2020 0 0 0)"
    }

    let encoded = ColorComponents(
      red: rec2020Encode(components.red),
      green: rec2020Encode(components.green),
      blue: rec2020Encode(components.blue)
    )
    return cssString(name: "rec2020", components: encoded, precision: precision)
  }

  /// Formats an extended sRGB color as linear Rec. 2100/Rec. 2020.
  public static func cssRec2100LinearString(
    from color: NSColor,
    precision: Int = 4
  ) -> String {
    guard let components = linearRec2020Components(from: color) else {
      return "color(rec2100-linear 0 0 0)"
    }
    return cssString(name: "rec2100-linear", components: components, precision: precision)
  }

  /// Formats an extended sRGB color with the Rec. 2100 PQ transfer curve.
  /// PQ is a display-referred encoding, so negative values are clipped to
  /// zero and values above the nominal range are clipped to one.
  public static func cssRec2100PQString(
    from color: NSColor,
    precision: Int = 4
  ) -> String {
    guard let components = linearRec2020Components(from: color) else {
      return "color(rec2100-pq 0 0 0)"
    }

    let encoded = ColorComponents(
      red: pqEncode(components.red),
      green: pqEncode(components.green),
      blue: pqEncode(components.blue)
    )
    return cssString(name: "rec2100-pq", components: encoded, precision: precision)
  }

  /// Formats an extended sRGB color with the Rec. 2100 HLG transfer curve.
  public static func cssRec2100HLGString(
    from color: NSColor,
    precision: Int = 4
  ) -> String {
    guard let components = linearRec2020Components(from: color) else {
      return "color(rec2100-hlg 0 0 0)"
    }

    let encoded = ColorComponents(
      red: hlgEncode(components.red),
      green: hlgEncode(components.green),
      blue: hlgEncode(components.blue)
    )
    return cssString(name: "rec2100-hlg", components: encoded, precision: precision)
  }

  /// Formats an extended sRGB color in the perceptual OKLCH space.
  public static func cssOKLCHString(
    from color: NSColor,
    precision: Int = 4
  ) -> String {
    guard let components = extendedSRGBComponents(from: color) else {
      return "oklch(0% 0 0)"
    }

    let lab = oklab(fromExtendedSRGB: components)
    let chroma = hypot(lab.a, lab.b)
    var hue = atan2(lab.b, lab.a) * 180 / .pi
    if hue < 0 {
      hue += 360
    }

    return String(
      format: "oklch(%0.*f%% %0.*f %0.*f)",
      precision,
      Double(lab.lightness * 100),
      precision,
      Double(chroma),
      precision,
      Double(hue)
    )
  }

  private static func cssString(
    name: String,
    components: ColorComponents,
    precision: Int
  ) -> String {
    let format = "color(\(name) %0.*f %0.*f %0.*f)"
    return String(
      format: format,
      precision, Double(components.red),
      precision, Double(components.green),
      precision, Double(components.blue)
    )
  }

  private static func linearRec2020Components(from color: NSColor) -> ColorComponents? {
    guard let sRGB = extendedSRGBComponents(from: color) else {
      return nil
    }

    let linearSRGB = ColorComponents(
      red: signedSRGBToLinear(sRGB.red),
      green: signedSRGBToLinear(sRGB.green),
      blue: signedSRGBToLinear(sRGB.blue)
    )
    let xyz = xyzD65(fromLinearSRGB: linearSRGB)

    return ColorComponents(
      red: 1.716651187971 * xyz.x - 0.355670783776 * xyz.y - 0.253366281374 * xyz.z,
      green: -0.666684351832 * xyz.x + 1.616481236635 * xyz.y + 0.015768545813 * xyz.z,
      blue: 0.017639857445 * xyz.x - 0.042770613258 * xyz.y + 0.942103121235 * xyz.z
    )
  }

  private static func oklab(fromExtendedSRGB components: ColorComponents) -> (lightness: CGFloat, a: CGFloat, b: CGFloat) {
    let linearSRGB = ColorComponents(
      red: signedSRGBToLinear(components.red),
      green: signedSRGBToLinear(components.green),
      blue: signedSRGBToLinear(components.blue)
    )
    let xyz = xyzD65(fromLinearSRGB: linearSRGB)

    let l = cubeRoot(0.8189330101 * xyz.x + 0.3618667424 * xyz.y - 0.1288597137 * xyz.z)
    let m = cubeRoot(0.0329845436 * xyz.x + 0.9293118715 * xyz.y + 0.0361456387 * xyz.z)
    let s = cubeRoot(0.0482003018 * xyz.x + 0.2643662691 * xyz.y + 0.6338517070 * xyz.z)

    return (
      0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    )
  }

  private static func xyzD65(fromLinearSRGB components: ColorComponents) -> (x: CGFloat, y: CGFloat, z: CGFloat) {
    (
      0.4123907993 * components.red + 0.3575843394 * components.green + 0.1804807884 * components.blue,
      0.2126390059 * components.red + 0.7151686788 * components.green + 0.0721923154 * components.blue,
      0.0193308187 * components.red + 0.1191947798 * components.green + 0.9505321522 * components.blue
    )
  }

  private static func signedSRGBToLinear(_ value: CGFloat) -> CGFloat {
    let magnitude = abs(value)
    let linear = magnitude <= 0.04045
      ? magnitude / 12.92
      : pow((magnitude + 0.055) / 1.055, 2.4)
    return value < 0 ? -linear : linear
  }

  private static func rec2020Encode(_ value: CGFloat) -> CGFloat {
    let magnitude = abs(value)
    let encoded = magnitude < 0.018053968510807
      ? 4.5 * magnitude
      : 1.09929682680944 * pow(magnitude, 0.45) - 0.09929682680944
    return value < 0 ? -encoded : encoded
  }

  private static func pqEncode(_ value: CGFloat) -> CGFloat {
    let normalized = max(0, value) * 203 / 10_000
    let n: CGFloat = 2610.0 / 16_384.0
    let m: CGFloat = 2523.0 / 32.0
    let c1: CGFloat = 3424.0 / 4096.0
    let c2: CGFloat = 2413.0 / 128.0
    let c3: CGFloat = 2392.0 / 128.0
    let powered = pow(normalized, n)
    let encoded = pow((c1 + c2 * powered) / (1 + c3 * powered), m)
    return min(max(encoded, 0), 1)
  }

  private static func hlgEncode(_ value: CGFloat) -> CGFloat {
    let a: CGFloat = 0.17883277
    let b: CGFloat = 1 - 4 * a
    let c: CGFloat = 0.5 - a * log(4 * a)
    let normalized = max(0, value) / 3.7743
    let encoded = normalized <= 1 / 12
      ? sqrt(3 * normalized)
      : a * log(12 * normalized - b) + c
    return min(max(encoded, 0), 1)
  }

  private static func cubeRoot(_ value: CGFloat) -> CGFloat {
    guard value != 0 else {
      return 0
    }
    let root = pow(abs(value), 1.0 / 3.0)
    return value < 0 ? -root : root
  }

  /// Returns the original color for SDR content, preserving its source gamut.
  /// HDR content is tone-mapped in linear Display P3; the original components
  /// remain available for export and copying.
  public static func displayColor(from color: NSColor) -> NSColor {
    guard isHDR(color),
          let components = extendedDisplayP3Components(from: color),
          let extendedDisplayP3ColorSpace
    else {
      return color
    }

    let peak = max(1, max(components.red, max(components.green, components.blue)))
    let mapped: (CGFloat) -> CGFloat = { value in
      clampedUnit(max(value, 0) / peak)
    }

    return NSColor(
      colorSpace: extendedDisplayP3ColorSpace,
      components: [
        mapped(components.red),
        mapped(components.green),
        mapped(components.blue),
        clampedUnit(components.alpha)
      ],
      count: 4
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
