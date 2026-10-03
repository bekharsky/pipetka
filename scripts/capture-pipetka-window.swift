import AppKit
import CoreVideo
import Foundation
import ScreenCaptureKit

@main
struct CapturePipetkaWindow {
  @MainActor
  static func main() async throws {
    guard CommandLine.arguments.count == 2 else {
      throw CaptureError.usage
    }

    _ = NSApplication.shared
    let destination = URL(fileURLWithPath: CommandLine.arguments[1])
    let content = try await SCShareableContent.excludingDesktopWindows(
      false,
      onScreenWindowsOnly: true
    )
    guard
      let window = content.windows.first(where: {
        $0.owningApplication?.bundleIdentifier == "com.kharion.pipetka"
          && $0.title == "Pipetka"
          && $0.isOnScreen
      })
    else {
      throw CaptureError.windowNotFound
    }

    let filter = SCContentFilter(desktopIndependentWindow: window)
    let configuration = SCStreamConfiguration()
    configuration.width = max(1, Int(window.frame.width * 2))
    configuration.height = max(1, Int(window.frame.height * 2))
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.showsCursor = false

    let image = try await SCScreenshotManager.captureImage(
      contentFilter: filter,
      configuration: configuration
    )
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw CaptureError.encodingFailed
    }

    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: destination, options: .atomic)
    print("Saved \(image.width)×\(image.height) Pipetka window to \(destination.path)")
  }
}

private enum CaptureError: Error, LocalizedError {
  case usage
  case windowNotFound
  case encodingFailed

  var errorDescription: String? {
    switch self {
    case .usage:
      return "Usage: swift scripts/capture-pipetka-window.swift <output.png>"
    case .windowNotFound:
      return "The visible Pipetka window was not found."
    case .encodingFailed:
      return "Could not encode the Pipetka screenshot as PNG."
    }
  }
}
