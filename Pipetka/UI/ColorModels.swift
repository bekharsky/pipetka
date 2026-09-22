import Cocoa
import PipetkaCore

enum ColorFormat: Int, CaseIterable {
  case hex
  case rgb
  case hsl
  case extendedRGB
  case swiftUI

  var label: String {
    switch self {
    case .hex:
      return "HEX"
    case .rgb:
      return "RGB"
    case .hsl:
      return "HSL"
    case .extendedRGB:
      return "CSS HDR"
    case .swiftUI:
      return "SwiftUI"
    }
  }
}

enum CSSColorSpace: String, CaseIterable, Identifiable {
  case sRGB
  case displayP3

  var id: String { rawValue }

  var label: String {
    switch self {
    case .sRGB:
      return "sRGB"
    case .displayP3:
      return "Display P3"
    }
  }

  var cssName: String {
    switch self {
    case .sRGB:
      return "srgb"
    case .displayP3:
      return "display-p3"
    }
  }

  var nsColorSpace: NSColorSpace {
    switch self {
    case .sRGB:
      return .extendedSRGB
    case .displayP3:
      return ColorUtilities.extendedDisplayP3ColorSpace ?? .extendedSRGB
    }
  }
}

struct PickedColor: Identifiable {
  let id = UUID()
  let color: NSColor
  let previewImage: NSImage?
  let pickedAt: Date

  var extendedSRGBColor: NSColor {
    color.usingColorSpace(.extendedSRGB) ?? color
  }

  var rgbColor: NSColor {
    extendedSRGBColor
  }

  var displayColor: NSColor {
    ColorUtilities.displayColor(from: extendedSRGBColor)
  }

  /// The color used by the small UI swatches. Keep extended values intact so
  /// AppKit can render them on an HDR display; the SDR tone-mapped color is
  /// still used when the source is an ordinary color.
  var previewColor: NSColor {
    isExtendedRange ? color : displayColor
  }

  var extendedComponents: ExtendedSRGBComponents? {
    ColorUtilities.extendedSRGBComponents(from: extendedSRGBColor)
  }

  var isExtendedRange: Bool {
    guard let extendedComponents else { return false }
    return ColorUtilities.isExtendedRange(extendedComponents)
  }

  var red: Int {
    ColorUtilities.byteComponent(extendedComponents?.red ?? 0)
  }

  var green: Int {
    ColorUtilities.byteComponent(extendedComponents?.green ?? 0)
  }

  var blue: Int {
    ColorUtilities.byteComponent(extendedComponents?.blue ?? 0)
  }

  var displayHex: String {
    ColorUtilities.hexString(from: displayColor)
  }

  var displayRGB: String {
    "rgb(\(ColorUtilities.byteComponent(displayColor.redComponent)), \(ColorUtilities.byteComponent(displayColor.greenComponent)), \(ColorUtilities.byteComponent(displayColor.blueComponent)))"
  }
}

struct RecentPickMenuItem {
  let text: String
  let color: NSColor
}

struct ImportedPalette: Identifiable {
  let id = UUID()
  let colors: [PickedColor]
  let previewImage: NSImage?
  let sourceName: String?
  let importedAt: Date
}

enum PaletteExportFormat: Int, CaseIterable {
  case cssVariables
  case scssVariables
  case tailwindColors
  case jsonTokens

  var label: String {
    switch self {
    case .cssVariables:
      return "CSS Variables"
    case .scssVariables:
      return "SCSS Variables"
    case .tailwindColors:
      return "Tailwind Colors"
    case .jsonTokens:
      return "JSON Tokens"
    }
  }
}

func formatColor(
  _ item: PickedColor,
  format: ColorFormat,
  cssColorSpace: CSSColorSpace = .sRGB
) -> String {
  switch format {
  case .hex:
    let value = item.isExtendedRange
      ? item.displayHex
      : String(format: "#%02X%02X%02X", item.red, item.green, item.blue)
    return item.isExtendedRange ? "HDR \(value) (use CSS HDR)" : value
  case .rgb:
    let value = item.isExtendedRange
      ? item.displayRGB
      : "rgb(\(item.red), \(item.green), \(item.blue))"
    return item.isExtendedRange ? "HDR \(value) (use CSS HDR)" : value
  case .hsl:
    let value = formatHsl(item)
    return item.isExtendedRange ? "HDR \(value) (use CSS HDR)" : value
  case .extendedRGB:
    return ColorUtilities.cssColorString(
      from: item.color,
      in: cssColorSpace.nsColorSpace,
      cssName: cssColorSpace.cssName
    )
  case .swiftUI:
    let components = item.extendedComponents ?? ExtendedSRGBComponents(red: 0, green: 0, blue: 0)
    if item.isExtendedRange {
      return String(
        format: "Color(nsColor: NSColor(colorSpace: .extendedSRGB, components: [%.3f, %.3f, %.3f, 1.000], count: 4))",
        Double(components.red),
        Double(components.green),
        Double(components.blue)
      )
    }
    return String(
      format: "Color(red: %.3f, green: %.3f, blue: %.3f)",
      Double(components.red),
      Double(components.green),
      Double(components.blue)
    )
  }
}

func displayFormatColor(
  _ item: PickedColor,
  format: ColorFormat,
  cssColorSpace: CSSColorSpace = .sRGB
) -> String {
  let value = formatColor(item, format: format, cssColorSpace: cssColorSpace)
  guard format == .swiftUI, value.hasPrefix("Color(nsColor: NSColor(") else {
    return value
  }

  var displayValue = value
  if let componentsStart = displayValue.range(of: "components: ["),
     let componentsEnd = displayValue.range(
       of: "], count: 4))",
       range: componentsStart.upperBound..<displayValue.endIndex
     ) {
    let componentValues = displayValue[componentsStart.upperBound..<componentsEnd.lowerBound]
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
    let components = stride(from: 0, to: componentValues.count, by: 2)
      .map { index in
        componentValues[index..<min(index + 2, componentValues.count)].joined(separator: ", ")
      }
      .joined(separator: ",\n      ")
    displayValue.replaceSubrange(
      componentsStart.lowerBound..<componentsEnd.lowerBound,
      with: "components: [\(components)]"
    )
  }

  return displayValue
    .replacingOccurrences(
      of: "Color(nsColor: NSColor(",
      with: "Color(nsColor:\n  NSColor(\n    "
    )
    .replacingOccurrences(of: ", components: [", with: ",\n    components: [")
    .replacingOccurrences(of: ", count: 4))", with: ",\n    count: 4\n  )\n)")
}

func formatHsl(_ item: PickedColor) -> String {
  let displayColor = item.displayColor
  let red = Double(ColorUtilities.clampedUnit(displayColor.redComponent))
  let green = Double(ColorUtilities.clampedUnit(displayColor.greenComponent))
  let blue = Double(ColorUtilities.clampedUnit(displayColor.blueComponent))
  let maxValue = max(red, max(green, blue))
  let minValue = min(red, min(green, blue))
  let delta = maxValue - minValue

  var hue = 0.0
  let lightness = (maxValue + minValue) / 2
  let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))

  if delta != 0 {
    if maxValue == red {
      hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
    } else if maxValue == green {
      hue = 60 * (((blue - red) / delta) + 2)
    } else {
      hue = 60 * (((red - green) / delta) + 4)
    }
  }

  if hue < 0 {
    hue += 360
  }

  return "hsl(\(Int(round(hue))) \(Int(round(saturation * 100)))% \(Int(round(lightness * 100)))%)"
}

func namedColorMatch(for item: PickedColor) -> NamedColorMatch {
  NamedColorLookup.nearestMatch(red: item.red, green: item.green, blue: item.blue)
}

func namedColorName(for item: PickedColor) -> String {
  if item.isExtendedRange {
    return "HDR color"
  }
  return namedColorMatch(for: item).name
}

func historySubtitle(
  for item: PickedColor,
  cssColorSpace: CSSColorSpace = .sRGB
) -> String {
  let value = item.isExtendedRange
    ? formatColor(item, format: .extendedRGB, cssColorSpace: cssColorSpace)
    : formatColor(item, format: .hex)
  return item.isExtendedRange ? "HDR • \(value)" : "\(namedColorName(for: item)) • \(value)"
}

func recentPickMenuText(
  for item: PickedColor,
  format: ColorFormat,
  cssColorSpace: CSSColorSpace = .sRGB
) -> String {
  "\(namedColorName(for: item)) - \(formatColor(item, format: format, cssColorSpace: cssColorSpace))"
}

func exportColors(
  _ items: [PickedColor],
  format: PaletteExportFormat,
  cssColorSpace: CSSColorSpace = .sRGB
) -> String {
  let entries = makeExportEntries(from: items)

  switch format {
  case .cssVariables:
    let body = entries.map { entry in
      "  --\(entry.slug): \(cssExportValue(for: entry.item, cssColorSpace: cssColorSpace)); /* \(entry.name) */"
    }.joined(separator: "\n")
    return ":root {\n\(body)\n}"
  case .scssVariables:
    return entries.map { entry in
      "$\(entry.slug): \(cssExportValue(for: entry.item, cssColorSpace: cssColorSpace)); // \(entry.name)"
    }.joined(separator: "\n")
  case .tailwindColors:
    let body = entries.map { entry in
      "      '\(entry.slug)': '\(cssExportValue(for: entry.item, cssColorSpace: cssColorSpace))', // \(entry.name)"
    }.joined(separator: "\n")
    return """
module.exports = {
  theme: {
    extend: {
      colors: {
\(body)
      }
    }
  }
}
"""
  case .jsonTokens:
    let body = entries.map { entry in
      """
  "\(entry.slug)": {
    "name": "\(escapeJSONString(entry.name))",
    "hex": "\(formatColor(entry.item, format: .hex, cssColorSpace: cssColorSpace))",
    "rgb": "\(formatColor(entry.item, format: .rgb, cssColorSpace: cssColorSpace))",
    "hsl": "\(formatColor(entry.item, format: .hsl, cssColorSpace: cssColorSpace))",
    "extendedRGB": "\(formatColor(entry.item, format: .extendedRGB, cssColorSpace: cssColorSpace))",
    "swiftUI": "\(formatColor(entry.item, format: .swiftUI))"
  }
"""
    }.joined(separator: ",\n")
    return "{\n\(body)\n}"
  }
}

private func cssExportValue(
  for item: PickedColor,
  cssColorSpace: CSSColorSpace
) -> String {
  item.isExtendedRange
    ? formatColor(item, format: .extendedRGB, cssColorSpace: cssColorSpace)
    : formatColor(item, format: .hex)
}

private struct ExportEntry {
  let slug: String
  let name: String
  let item: PickedColor
}

private func makeExportEntries(from items: [PickedColor]) -> [ExportEntry] {
  var usedSlugs: [String: Int] = [:]

  return items.map { item in
    let name = namedColorName(for: item)
    let baseSlug = slugifyColorName(name)
    let count = usedSlugs[baseSlug, default: 0]
    usedSlugs[baseSlug] = count + 1
    let slug = count == 0 ? baseSlug : "\(baseSlug)-\(count + 1)"
    return ExportEntry(slug: slug, name: name, item: item)
  }
}

private func slugifyColorName(_ name: String) -> String {
  let lowercase = name.lowercased()
  let scalars = lowercase.unicodeScalars.map { scalar -> Character in
    CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
  }
  let raw = String(scalars)
  let collapsed = raw.replacingOccurrences(
    of: "-+",
    with: "-",
    options: .regularExpression
  )
  let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  return trimmed.isEmpty ? "color" : trimmed
}

private func escapeJSONString(_ string: String) -> String {
  string
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
}
