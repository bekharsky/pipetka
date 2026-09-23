import AppKit
import PipetkaCore
import Foundation

final class MCPServer {
  private var picker: ScreenColorPicker?
  private var pendingRequestId: Any?
  private let windowManager = WindowManager()

  // MARK: - Stdin read loop (runs on a background thread)

  func readLoop() {
    while let line = readLine(strippingNewline: true) {
      guard !line.isEmpty else { continue }
      DispatchQueue.main.async { [weak self] in
        self?.handle(line: line)
      }
    }
    // stdin closed — shut down gracefully
    DispatchQueue.main.async { NSApp.terminate(nil) }
  }

  // MARK: - JSON-RPC dispatch (runs on main thread)

  private func handle(line: String) {
    guard
      let data = line.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let method = json["method"] as? String
    else {
      return
    }

    let id = json["id"]

    switch method {
    case "initialize":
      respond(id: id, result: [
        "protocolVersion": "2024-11-05",
        "capabilities": ["tools": [String: Any]()],
        "serverInfo": ["name": "pipetka-mcp", "version": "1.0.0"]
      ])

    case "notifications/initialized":
      break  // notification — no response expected

    case "ping":
      respond(id: id, result: [String: Any]())

    case "tools/list":
      respond(id: id, result: [
        "tools": [
          [
            "name": "pick_color",
            "description": "Opens an interactive magnifier overlay on screen. The user clicks any pixel to sample its color. Returns SDR hex/rgb/hsl values plus extendedRGB in CSS color(srgb ...) syntax for HDR colors. IMPORTANT: Always display the full color result to the user exactly as returned.",
            "inputSchema": ["type": "object", "properties": [String: Any]()]
          ] as [String: Any],
          [
            "name": "extract_palette",
            "description": "Opens a file-picker so the user can choose an image, picture, photo, or file. Extracts the dominant colors from it and returns hex, rgb, and hsl values for every color. Use this when the user says things like: 'extract colors from an image', 'create a palette from a picture', 'get colors from a file', 'extract palette from photo', 'what colors are in this image', 'pull colors from a picture'. IMPORTANT: Always display the COMPLETE palette table to the user exactly as returned — do not summarize or omit any rows.",
            "inputSchema": ["type": "object", "properties": [String: Any]()]
          ] as [String: Any]
        ]
      ])

    case "tools/call":
      guard
        let params = json["params"] as? [String: Any],
        let toolName = params["name"] as? String
      else {
        respondError(id: id, code: -32602, message: "Unknown tool or invalid params")
        return
      }
      guard pendingRequestId == nil else {
        respondError(id: id, code: -32000, message: "A tool call is already in progress")
        return
      }
      switch toolName {
      case "pick_color":
        pendingRequestId = id
        startPicker()
      case "extract_palette":
        pendingRequestId = id
        startPaletteExtraction()
      default:
        respondError(id: id, code: -32602, message: "Unknown tool: \(toolName)")
      }

    default:
      if id != nil {
        respondError(id: id, code: -32601, message: "Method not found: \(method)")
      }
    }
  }

  // MARK: - Picker lifecycle

  private func startPicker() {
    // Capture the frontmost app BEFORE starting the picker
    // because the picker will activate our app, changing the frontmost app
    windowManager.captureFrontmostApp()
    
    picker = ScreenColorPicker(
      hideWindow: { [weak self] in
        self?.windowManager.hideWindow()
      },
      showWindow: { [weak self] in
        self?.windowManager.showHiddenWindow()
      },
      onPick: { [weak self] payload in
        self?.handlePick(payload)
      },
      onCancel: { [weak self] in
        self?.handleCancel()
      }
    )
    picker?.start()
  }

  private func handlePick(_ payload: PickedColorPayload) {
    let id = pendingRequestId
    pendingRequestId = nil
    picker = nil

    let r = payload.red, g = payload.green, b = payload.blue
    let hsl = ColorUtilities.rgbToHsl(r: r, g: g, b: b)

    // Create color bucket for swatch generation
    let bucket = PaletteColorBucket(color: payload.color, pixelCount: 1)
    let swatch = "![\(payload.hex)](\(swatchDataURI(for: bucket)))"
    let extendedRGB = ColorUtilities.cssExtendedSRGBString(from: payload.color)
    
    // Get color name
    let match = NamedColorLookup.nearestMatch(red: r, green: g, blue: b)

    let lines = [
      "\(swatch) \(match.name)",
      "hex: \(payload.hex)",
      "rgb: rgb(\(r), \(g), \(b))",
      "hsl: hsl(\(hsl.h), \(hsl.s)%, \(hsl.l)%)",
      "extendedRGB: \(extendedRGB)"
    ]
    
    var content: [[String: Any]] = []
    content.append(["type": "text", "text": lines.joined(separator: "\n")])

    respond(id: id, result: ["content": content])
  }

  private func handleCancel() {
    let id = pendingRequestId
    pendingRequestId = nil
    picker = nil
    respondError(id: id, code: -32000, message: "Color picking was cancelled")
  }

  // MARK: - Palette extraction lifecycle

  private func startPaletteExtraction() {
    pickImageAndExtractPalette { [weak self] filename, palette in
      self?.handlePaletteResult(filename: filename, palette: palette)
    }
  }

  private func handlePaletteResult(filename: String?, palette: [PaletteColorBucket]?) {
    let id = pendingRequestId
    pendingRequestId = nil

    guard let filename, let palette, !palette.isEmpty else {
      respondError(id: id, code: -32000, message: "Palette extraction was cancelled or the image could not be read")
      return
    }

    var content: [[String: Any]] = []

    // Precompute swatches and names
    struct Row {
      let swatch: String
      let hex: String
      let name: String
    }
    let rows: [Row] = palette.map { bucket in
      let swatch = "![\(bucket.hex)](\(swatchDataURI(for: bucket)))"
      let match = NamedColorLookup.nearestMatch(red: bucket.red, green: bucket.green, blue: bucket.blue)
      return Row(swatch: swatch, hex: bucket.hex, name: match.name)
    }

    // Build table
    var lines: [String] = [
      "Palette from: **\(filename)** (\(palette.count) colors)",
      "",
      "| | Hex | Name |",
      "|---|---|---|"
    ]
    for row in rows {
      lines.append("| \(row.swatch) | `\(row.hex)` | \(row.name) |")
    }
    content.append(["type": "text", "text": lines.joined(separator: "\n")])

    respond(id: id, result: ["content": content])
  }

  // MARK: - JSON-RPC helpers

  private func respond(id: Any?, result: Any) {
    var response: [String: Any] = ["jsonrpc": "2.0", "result": result]
    if let id { response["id"] = id }
    writeJSON(response)
  }

  private func respondError(id: Any?, code: Int, message: String) {
    var response: [String: Any] = [
      "jsonrpc": "2.0",
      "error": ["code": code, "message": message] as [String: Any]
    ]
    if let id { response["id"] = id }
    writeJSON(response)
  }

  private func writeJSON(_ object: [String: Any]) {
    guard
      let data = try? JSONSerialization.data(withJSONObject: object),
      let line = String(data: data, encoding: .utf8)
    else { return }
    // Write directly to the fd so output is never buffered
    FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
  }

}
