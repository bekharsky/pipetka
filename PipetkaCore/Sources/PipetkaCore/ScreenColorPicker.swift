// Screen color picker with magnifier lens
import Cocoa
import CoreMedia
import CoreVideo
import ScreenCaptureKit

public struct PickedColorPayload {
  public let color: NSColor
  public let previewPng: Data

  private var components: ExtendedSRGBComponents? {
    ColorUtilities.extendedSRGBComponents(from: color)
  }

  public var red: Int { ColorUtilities.byteComponent(components?.red ?? 0) }
  public var green: Int { ColorUtilities.byteComponent(components?.green ?? 0) }
  public var blue: Int { ColorUtilities.byteComponent(components?.blue ?? 0) }
  public var hex: String { ColorUtilities.hexString(from: color) }

  public init(color: NSColor, previewPng: Data) {
    self.color = color
    self.previewPng = previewPng
  }

  @available(*, deprecated, message: "Use init(color:previewPng:) to preserve extended-range color values")
  public init(red: Int, green: Int, blue: Int, hex: String, previewPng: Data) {
    self.color = NSColor(
      srgbRed: CGFloat(red) / 255,
      green: CGFloat(green) / 255,
      blue: CGFloat(blue) / 255,
      alpha: 1
    )
    self.previewPng = previewPng
  }
}

public final class ScreenColorPicker {
  private let hideWindow: () -> Void
  private let showWindow: () -> Void
  private let onPick: (PickedColorPayload) -> Void
  private let onCancel: (() -> Void)?
  private let pixelSampler: PixelSampler
  private var overlayPanels: [PickerOverlayPanel] = []
  private var lensPanel: PickerLensPanel?
  private var lensView: PickerLensView?
  private var selectionPoint: CGPoint?
  private var samplingGeneration = 0

  public init(
    hideWindow: @escaping () -> Void,
    showWindow: @escaping () -> Void,
    onPick: @escaping (PickedColorPayload) -> Void,
    onCancel: (() -> Void)? = nil,
    usesTestSampling: Bool = false
  ) {
    self.hideWindow = hideWindow
    self.showWindow = showWindow
    self.onPick = onPick
    self.onCancel = onCancel
    self.pixelSampler = PixelSampler(usesTestSampling: usesTestSampling)
  }

  public func start() {
    guard overlayPanels.isEmpty, lensPanel == nil else {
      return
    }

    hideWindow()
    samplingGeneration += 1
    pixelSampler.prepareHDRCapture()

    for screen in NSScreen.screens {
      let panel = PickerOverlayPanel(
        contentRect: screen.frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      let view = PickerOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
      view.bridge = self
      view.screenFrame = screen.frame

      panel.contentView = view
      configurePickerPanel(panel)
      overlayPanels.append(panel)
    }

    let lensSize = CGSize(width: 184, height: 216)
    let lensPanel = PickerLensPanel(
      contentRect: CGRect(origin: .zero, size: lensSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    let lensView = PickerLensView(frame: CGRect(origin: .zero, size: lensSize))
    lensView.bridge = self
    lensPanel.contentView = lensView
    configureLensPanel(lensPanel)
    lensPanel.ignoresMouseEvents = true

    self.lensPanel = lensPanel
    self.lensView = lensView

    NSApp.activate(ignoringOtherApps: true)
    NSCursor.crosshair.push()

    overlayPanels.forEach { panel in
      panel.orderFrontRegardless()
      panel.makeKey()
    }
    lensPanel.orderFrontRegardless()
    refresh(at: NSEvent.mouseLocation)
  }

  fileprivate func complete(with sample: PixelSample) {
    tearDownOverlay()
    showWindow()
    onPick(
      PickedColorPayload(
        color: sample.color,
        previewPng: sample.previewPng
      )
    )
  }

  fileprivate func confirmKeyboardSelection() {
    let point = selectionPoint ?? NSEvent.mouseLocation
    confirmSelection(at: point)
  }

  fileprivate func moveSelection(by offset: CGVector) {
    let currentPoint = selectionPoint ?? NSEvent.mouseLocation
    let proposedPoint = CGPoint(
      x: currentPoint.x + offset.dx,
      y: currentPoint.y + offset.dy
    )
    let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(currentPoint) })?.frame
      ?? NSScreen.main?.frame
      ?? .zero
    let point = CGPoint(
      x: min(max(proposedPoint.x, screenFrame.minX), screenFrame.maxX - 1),
      y: min(max(proposedPoint.y, screenFrame.minY), screenFrame.maxY - 1)
    )
    refresh(at: point)
  }

  func cancel() {
    tearDownOverlay()
    showWindow()
    onCancel?()
  }

  fileprivate func refresh(at mousePoint: CGPoint) {
    selectionPoint = mousePoint
    let generation = samplingGeneration
    pixelSampler.sample(at: mousePoint, requiresHDR: false) { [weak self] sample in
      guard let self, let sample, generation == self.samplingGeneration,
            self.selectionPoint == mousePoint else {
        return
      }
      self.display(sample: sample, at: mousePoint)
    }
  }

  fileprivate func confirmSelection(at point: CGPoint) {
    let generation = samplingGeneration
    pixelSampler.sample(at: point, requiresHDR: true) { [weak self] sample in
      guard let self, let sample, generation == self.samplingGeneration else {
        return
      }
      self.complete(with: sample)
    }
  }

  private func display(sample: PixelSample, at point: CGPoint) {
    lensView?.sample = sample
    lensView?.mousePoint = point
    lensView?.needsDisplay = true

    guard let lensPanel else {
      return
    }

    let lensFrame = PickerLensView.frameForLens(
      around: point,
      visibleFrame: sample.screenFrame
    )
    lensPanel.setFrame(lensFrame, display: true)
    lensPanel.orderFrontRegardless()
  }

  private func tearDownOverlay() {
    samplingGeneration += 1
    pixelSampler.cancel()
    overlayPanels.forEach { $0.orderOut(nil) }
    overlayPanels.removeAll()
    lensPanel?.orderOut(nil)
    lensPanel = nil
    lensView = nil
    selectionPoint = nil
    NSCursor.pop()
  }

  private func configurePickerPanel(_ panel: NSPanel) {
    panel.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.001)
    panel.level = NSWindow.Level(
      rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow))
    )
    panel.isOpaque = false
    panel.hasShadow = false
    panel.sharingType = .none
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .ignoresCycle
    ]
    panel.acceptsMouseMovedEvents = true
  }

  private func configureLensPanel(_ panel: NSPanel) {
    configurePickerPanel(panel)
    panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    panel.hasShadow = true
    panel.backgroundColor = .clear
  }
}

final class PickerOverlayPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

final class PickerLensPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

final class PickerOverlayView: NSView {
  weak var bridge: ScreenColorPicker?
  var screenFrame: CGRect = .zero
  private var heldArrowKey: UInt16?
  private var arrowKeyPressTimestamp: TimeInterval?

  override var acceptsFirstResponder: Bool { true }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.makeFirstResponder(self)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    return self
  }

  override func mouseMoved(with event: NSEvent) {
    bridge?.refresh(at: NSEvent.mouseLocation)
  }

  override func mouseDragged(with event: NSEvent) {
    bridge?.refresh(at: NSEvent.mouseLocation)
  }

  override func mouseDown(with event: NSEvent) {
    bridge?.confirmSelection(at: NSEvent.mouseLocation)
  }

  override func rightMouseDown(with event: NSEvent) {
    bridge?.cancel()
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 53:  // Escape
      bridge?.cancel()
    case 36, 49, 76:  // Return, Space, keypad Enter
      bridge?.confirmKeyboardSelection()
    case 123:  // Left arrow
      bridge?.moveSelection(by: CGVector(dx: -keyboardStep(for: event), dy: 0))
    case 124:  // Right arrow
      bridge?.moveSelection(by: CGVector(dx: keyboardStep(for: event), dy: 0))
    case 125:  // Down arrow
      bridge?.moveSelection(by: CGVector(dx: 0, dy: -keyboardStep(for: event)))
    case 126:  // Up arrow
      bridge?.moveSelection(by: CGVector(dx: 0, dy: keyboardStep(for: event)))
    default:
      super.keyDown(with: event)
    }
  }

  private func keyboardStep(for event: NSEvent) -> CGFloat {
    if !event.isARepeat || heldArrowKey != event.keyCode {
      heldArrowKey = event.keyCode
      arrowKeyPressTimestamp = event.timestamp
    }

    let heldDuration = event.timestamp - (arrowKeyPressTimestamp ?? event.timestamp)
    let acceleration: CGFloat
    switch heldDuration {
    case ..<0.35:
      acceleration = 1
    case ..<0.8:
      acceleration = 2
    case ..<1.4:
      acceleration = 5
    default:
      acceleration = 12
    }

    return acceleration * (event.modifierFlags.contains(.shift) ? 10 : 1)
  }
}

final class PickerLensView: NSView {
  weak var bridge: ScreenColorPicker?
  fileprivate var sample: PixelSample?
  var mousePoint: CGPoint = .zero

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    wantsLayer = true
  }

  static func frameForLens(around point: CGPoint, visibleFrame: CGRect) -> CGRect {
    let size = CGSize(width: 184, height: 216)
    var origin = CGPoint(x: point.x + 26, y: point.y - size.height - 18)

    if origin.x + size.width > visibleFrame.maxX - 18 {
      origin.x = point.x - size.width - 26
    }
    if origin.y < visibleFrame.minY + 18 {
      origin.y = point.y + 18
    }
    if origin.y + size.height > visibleFrame.maxY - 18 {
      origin.y = visibleFrame.maxY - size.height - 18
    }
    if origin.x < visibleFrame.minX + 18 {
      origin.x = visibleFrame.minX + 18
    }

    return CGRect(origin: origin, size: size)
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.clear.setFill()
    dirtyRect.fill()

    guard let sample, let context = NSGraphicsContext.current?.cgContext else {
      return
    }

    let lensRect = bounds
    let bubbleRadius: CGFloat = 20
    let bubblePath = NSBezierPath(
      roundedRect: lensRect,
      xRadius: bubbleRadius,
      yRadius: bubbleRadius
    )
    NSColor(calibratedWhite: 0.10, alpha: 0.96).setFill()
    bubblePath.fill()
    NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
    bubblePath.lineWidth = 1
    bubblePath.stroke()

    let previewInset: CGFloat = 12
    let previewHeight = lensRect.height - 48
    let previewRect = CGRect(
      x: lensRect.minX + previewInset,
      y: lensRect.minY + 36,
      width: lensRect.width - previewInset * 2,
      height: previewHeight
    )

    context.saveGState()
    let previewRadius = max(12, bubbleRadius - previewInset)
    let previewPath = NSBezierPath(
      roundedRect: previewRect,
      xRadius: previewRadius,
      yRadius: previewRadius
    )
    previewPath.addClip()
    context.interpolationQuality = .none
    context.draw(sample.previewImage, in: previewRect)
    drawGrid(in: previewRect, context: context)
    drawCenterMark(in: previewRect, context: context)
    context.restoreGState()

    let swatchRect = CGRect(x: 12, y: 10, width: 18, height: 18)
    ColorUtilities.displayColor(from: sample.color).setFill()
    NSBezierPath(roundedRect: swatchRect, xRadius: 6, yRadius: 6).fill()

    let label = sample.displayValue
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
      .foregroundColor: NSColor(calibratedWhite: 0.95, alpha: 1)
    ]
    label.draw(at: CGPoint(x: swatchRect.maxX + 8, y: 12), withAttributes: attributes)
  }

  private func drawGrid(in rect: CGRect, context: CGContext) {
    context.saveGState()
    context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.10).cgColor)
    context.setLineWidth(1)
    let cellSize = rect.width / 15
    for index in 1..<15 {
      let offset = rect.minX + CGFloat(index) * cellSize
      context.move(to: CGPoint(x: offset, y: rect.minY))
      context.addLine(to: CGPoint(x: offset, y: rect.maxY))
    }
    for index in 1..<15 {
      let offset = rect.minY + CGFloat(index) * cellSize
      context.move(to: CGPoint(x: rect.minX, y: offset))
      context.addLine(to: CGPoint(x: rect.maxX, y: offset))
    }
    context.strokePath()
    context.restoreGState()
  }

  private func drawCenterMark(in rect: CGRect, context: CGContext) {
    let cellSize = rect.width / 15
    let centerRect = CGRect(
      x: rect.midX - cellSize / 2,
      y: rect.midY - cellSize / 2,
      width: cellSize,
      height: cellSize
    )
    context.saveGState()
    context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.75).cgColor)
    context.setLineWidth(2)
    context.stroke(centerRect)
    context.restoreGState()
  }
}

// MARK: - Pixel sampling

private struct PixelSample {
  let color: NSColor
  let previewImage: CGImage
  let previewPng: Data
  let screenFrame: CGRect

  var components: ExtendedSRGBComponents? {
    ColorUtilities.extendedSRGBComponents(from: color)
  }

  var hex: String { ColorUtilities.hexString(from: color) }
  var isExtendedRange: Bool {
    guard let components else { return false }
    return ColorUtilities.isExtendedRange(components)
  }
  var displayValue: String {
    isExtendedRange ? ColorUtilities.cssExtendedSRGBString(from: color, precision: 2) : hex
  }
}

enum HDRColorDecoder {
  static func float(fromHalfBits bits: UInt16) -> Float {
    let sign = UInt32(bits & 0x8000) << 16
    let exponent = UInt32((bits >> 10) & 0x1F)
    let mantissa = UInt32(bits & 0x03FF)

    if exponent == 0 {
      guard mantissa != 0 else {
        return Float(bitPattern: sign)
      }

      var normalizedMantissa = mantissa
      var normalizedExponent: Int32 = -14
      while normalizedMantissa & 0x0400 == 0 {
        normalizedMantissa <<= 1
        normalizedExponent -= 1
      }
      normalizedMantissa &= 0x03FF
      let floatExponent = UInt32(normalizedExponent + 127)
      return Float(
        bitPattern: sign | (floatExponent << 23) | (normalizedMantissa << 13)
      )
    }

    if exponent == 0x1F {
      return Float(bitPattern: sign | 0x7F800000 | (mantissa << 13))
    }

    let floatExponent = UInt32(Int32(exponent) - 15 + 127)
    return Float(bitPattern: sign | (floatExponent << 23) | (mantissa << 13))
  }

  static func component(
    in bytes: UnsafePointer<UInt8>,
    at offset: Int
  ) -> CGFloat? {
    guard offset >= 0 else {
      return nil
    }

    let bits = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    let value = float(fromHalfBits: bits)
    guard value.isFinite else {
      return nil
    }
    return CGFloat(value)
  }

  static func makeColor(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
    alpha: CGFloat,
    colorSpace: CGColorSpace,
    isPremultiplied: Bool
  ) -> NSColor? {
    guard red.isFinite,
          green.isFinite,
          blue.isFinite,
          alpha.isFinite,
          alpha > 0,
          alpha <= 1 else {
      return nil
    }

    let divisor = isPremultiplied ? alpha : 1
    let components = [red / divisor, green / divisor, blue / divisor, alpha]
    guard components.dropLast().allSatisfy(\.isFinite),
          let cgColor = CGColor(colorSpace: colorSpace, components: components) else {
      return nil
    }

    return NSColor(cgColor: cgColor)?.usingColorSpace(.extendedSRGB)
  }
}

private final class PixelSampler {
  private let usesTestSampling: Bool
  private var hdrCapture: HDRPixelCapture?

  init(usesTestSampling: Bool) {
    self.usesTestSampling = usesTestSampling
  }

  func prepareHDRCapture() {
    guard !usesTestSampling, #available(macOS 15.0, *) else {
      return
    }

    if hdrCapture == nil {
      hdrCapture = HDRPixelCapture()
    }
    hdrCapture?.prepare()
  }

  func cancel() {
    hdrCapture?.cancel()
  }

  func sample(
    at point: CGPoint,
    requiresHDR: Bool,
    preview: PixelSample? = nil,
    completion: @escaping (PixelSample?) -> Void
  ) {
    guard
      let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
    else {
      completion(nil)
      return
    }

    if usesTestSampling {
      completion(Self.testSample(at: point, screen: screen))
      return
    }

    guard requiresHDR else {
      completion(Self.legacySample(at: point, screen: screen))
      return
    }

    if #available(macOS 15.0, *), let hdrCapture {
      guard let preview = preview ?? Self.legacySample(at: point, screen: screen) else {
        completion(nil)
        return
      }

      hdrCapture.sample(at: point, on: screen) { color in
        guard let color, Self.isUsableHDRColor(color) else {
          completion(preview)
          return
        }

        completion(
          PixelSample(
            color: color,
            previewImage: preview.previewImage,
            previewPng: preview.previewPng,
            screenFrame: preview.screenFrame
          )
        )
      }
      return
    }

    completion(Self.legacySample(at: point, screen: screen))
  }

  private static func isUsableHDRColor(_ color: NSColor) -> Bool {
    guard let components = ColorUtilities.extendedSRGBComponents(from: color) else {
      return false
    }

    return [components.red, components.green, components.blue].allSatisfy {
      $0.isFinite && $0 >= -1 && $0 <= 1024
    }
  }

  fileprivate static func legacySample(at point: CGPoint, screen: NSScreen) -> PixelSample? {
    guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
      return nil
    }

    let displayId = CGDirectDisplayID(displayNumber.uint32Value)
    let displayBounds = CGDisplayBounds(displayId)
    let widthRatio = displayBounds.width / screen.frame.width
    let heightRatio = displayBounds.height / screen.frame.height
    let localX = (point.x - screen.frame.minX) * widthRatio
    let localY = (point.y - screen.frame.minY) * heightRatio
    let pixelHeight = displayBounds.height
    let pixelWidth = displayBounds.width
    let pixelX = floor(localX)
    let pixelY = floor(pixelHeight - localY - 1)

    guard
      let pixelImage = CGDisplayCreateImage(
        displayId,
        rect: CGRect(x: pixelX, y: pixelY, width: 1, height: 1)
      ),
      let previewImage = previewImage(
        displayId: displayId,
        pixelX: pixelX,
        pixelY: pixelY,
        maxWidth: pixelWidth,
        maxHeight: pixelHeight
      ),
      let previewPng = pngData(for: previewImage)
    else {
      return nil
    }

    guard let color = color(from: pixelImage) else {
      return nil
    }

    return PixelSample(
      color: color,
      previewImage: previewImage,
      previewPng: previewPng,
      screenFrame: screen.visibleFrame
    )
  }

  private static func previewImage(
    displayId: CGDirectDisplayID,
    pixelX: CGFloat,
    pixelY: CGFloat,
    maxWidth: CGFloat,
    maxHeight: CGFloat
  ) -> CGImage? {
    let previewSize: CGFloat = 15
    let half = floor(previewSize / 2)
    let originX = max(0, min(pixelX - half, maxWidth - previewSize))
    let originY = max(0, min(pixelY - half, maxHeight - previewSize))
    return CGDisplayCreateImage(
      displayId,
      rect: CGRect(x: originX, y: originY, width: previewSize, height: previewSize)
    )
  }

  fileprivate static func pngData(for image: CGImage) -> Data? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    return bitmap.representation(using: .png, properties: [:])
  }

  fileprivate static func color(from pixelBuffer: CVPixelBuffer) -> NSColor? {
    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == 0x52476841,
          CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
      return nil
    }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      return nil
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    guard width > 0, height > 0, bytesPerRow >= 8 else {
      return nil
    }

    let x = width / 2
    let y = height / 2
    let pixelOffset = y * bytesPerRow + x * 8
    guard pixelOffset >= 0,
          pixelOffset + 8 <= CVPixelBufferGetDataSize(pixelBuffer) else {
      return nil
    }

    let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
    guard let red = HDRColorDecoder.component(in: bytes, at: pixelOffset),
          let green = HDRColorDecoder.component(in: bytes, at: pixelOffset + 2),
          let blue = HDRColorDecoder.component(in: bytes, at: pixelOffset + 4),
          let alpha = HDRColorDecoder.component(in: bytes, at: pixelOffset + 6) else {
      return nil
    }

    let colorSpace = CGColorSpace(name: CGColorSpace.extendedDisplayP3)
      ?? CGColorSpace(name: CGColorSpace.extendedSRGB)
    guard let colorSpace else {
      return nil
    }

    return HDRColorDecoder.makeColor(
      red: red,
      green: green,
      blue: blue,
      alpha: alpha,
      colorSpace: colorSpace,
      isPremultiplied: true
    )
  }

  private static func testSample(at point: CGPoint, screen: NSScreen) -> PixelSample? {
    let red = Int(point.x.rounded()) & 0xFF
    let green = Int(point.y.rounded()) & 0xFF
    let blue = (red &+ green) / 2
    let color = NSColor(
      srgbRed: CGFloat(red) / 255,
      green: CGFloat(green) / 255,
      blue: CGFloat(blue) / 255,
      alpha: 1
    )
    let imageSize = NSSize(width: 15, height: 15)
    let image = NSImage(size: imageSize)
    image.lockFocus()
    color.setFill()
    NSRect(origin: .zero, size: imageSize).fill()
    image.unlockFocus()

    guard
      let bitmap = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()),
      let previewImage = bitmap.cgImage,
      let previewPng = bitmap.representation(using: .png, properties: [:])
    else {
      return nil
    }

    return PixelSample(
      color: color,
      previewImage: previewImage,
      previewPng: previewPng,
      screenFrame: screen.visibleFrame
    )
  }

  fileprivate static func color(
    from image: CGImage,
    pixelX: Int = 0,
    pixelY: Int = 0
  ) -> NSColor? {
    if image.bitsPerComponent == 16,
       image.bitsPerPixel == 64,
       image.bitmapInfo.contains(.floatComponents) {
      guard
        let providerData = image.dataProvider?.data,
        let bytes = CFDataGetBytePtr(providerData)
      else {
        return nil
      }

      let x = min(max(pixelX, 0), image.width - 1)
      let y = min(max(pixelY, 0), image.height - 1)
      let pixelOffset = y * image.bytesPerRow + x * 8
      guard pixelOffset >= 0,
            pixelOffset + 8 <= CFDataGetLength(providerData) else {
        return nil
      }

      let channelOffsets: (red: Int, green: Int, blue: Int, alpha: Int?)
      let isPremultiplied: Bool
      switch image.alphaInfo {
      case .premultipliedLast:
        channelOffsets = (0, 2, 4, 6)
        isPremultiplied = true
      case .last:
        channelOffsets = (0, 2, 4, 6)
        isPremultiplied = false
      case .premultipliedFirst:
        channelOffsets = (2, 4, 6, 0)
        isPremultiplied = true
      case .first:
        channelOffsets = (2, 4, 6, 0)
        isPremultiplied = false
      case .noneSkipLast:
        channelOffsets = (0, 2, 4, nil)
        isPremultiplied = false
      case .noneSkipFirst:
        channelOffsets = (2, 4, 6, nil)
        isPremultiplied = false
      default:
        return nil
      }

      guard let red = HDRColorDecoder.component(
              in: bytes,
              at: pixelOffset + channelOffsets.red
            ),
            let green = HDRColorDecoder.component(
              in: bytes,
              at: pixelOffset + channelOffsets.green
            ),
            let blue = HDRColorDecoder.component(
              in: bytes,
              at: pixelOffset + channelOffsets.blue
            ) else {
        return nil
      }

      let alpha = channelOffsets.alpha.flatMap {
        HDRColorDecoder.component(in: bytes, at: pixelOffset + $0)
      } ?? 1

      let colorSpace = image.colorSpace
        ?? CGColorSpace(name: CGColorSpace.extendedSRGB)
      guard let colorSpace else {
        return nil
      }
      return HDRColorDecoder.makeColor(
        red: red,
        green: green,
        blue: blue,
        alpha: alpha,
        colorSpace: colorSpace,
        isPremultiplied: isPremultiplied
      )
    }

    let bitmap = NSBitmapImageRep(cgImage: image)
    let x = min(max(pixelX, 0), image.width - 1)
    let y = min(max(pixelY, 0), image.height - 1)
    guard let sampled = bitmap.colorAt(x: x, y: y) else {
      return nil
    }
    return sampled.usingColorSpace(.extendedSRGB) ?? sampled.usingColorSpace(.deviceRGB)
  }
}

private final class HDRPixelCapture {
  private struct PendingRequest {
    let point: CGPoint
    let screen: NSScreen
    let filter: SCContentFilter
    let pixelScale: CGFloat
    let generation: Int
    let completion: (NSColor?) -> Void
  }

  private var filters: [CGDirectDisplayID: SCContentFilter] = [:]
  private var isPreparing = false
  private var generation = 0
  private var pendingRequest: PendingRequest?
  private var isCaptureInFlight = false
  private var captureSequence = 0
  private var activeCaptureID: Int?
  private var scheduledStart: DispatchWorkItem?
  private var lastCaptureStart = 0.0

  private let minimumCaptureInterval = 1.0 / 30.0
  private let captureTimeout = 0.75

  func prepare() {
    guard !isPreparing, filters.isEmpty else {
      return
    }

    isPreparing = true
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) {
      [weak self] content, _ in
      DispatchQueue.main.async {
        guard let self else { return }
        self.isPreparing = false

        guard let content else {
          return
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let currentApplication = content.applications.first { $0.processID == currentProcessID }

        for display in content.displays {
          let filter: SCContentFilter
          if let currentApplication {
            filter = SCContentFilter(
              display: display,
              excludingApplications: [currentApplication],
              exceptingWindows: []
            )
          } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
          }
          self.filters[display.displayID] = filter
        }
      }
    }
  }

  func cancel() {
    generation += 1
    pendingRequest = nil
    scheduledStart?.cancel()
    scheduledStart = nil
    captureSequence += 1
    activeCaptureID = nil
    isCaptureInFlight = false
  }

  @available(macOS 15.0, *)
  func sample(
    at point: CGPoint,
    on screen: NSScreen,
    completion: @escaping (NSColor?) -> Void
  ) {
    guard
      let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
      let filter = filters[CGDirectDisplayID(displayNumber.uint32Value)]
    else {
      completion(nil)
      return
    }

    pendingRequest = PendingRequest(
      point: point,
      screen: screen,
      filter: filter,
      pixelScale: max(CGFloat(filter.pointPixelScale), 1),
      generation: generation,
      completion: completion
    )
    startNextCapture()
  }

  @available(macOS 15.0, *)
  private func startNextCapture() {
    guard !isCaptureInFlight, let request = pendingRequest else {
      return
    }

    let now = ProcessInfo.processInfo.systemUptime
    let delay = minimumCaptureInterval - (now - lastCaptureStart)
    if delay > 0 {
      guard scheduledStart == nil else { return }
      let workItem = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.scheduledStart = nil
        self.startNextCapture()
      }
      scheduledStart = workItem
      DispatchQueue.main.asyncAfter(
        deadline: .now() + delay,
        execute: workItem
      )
      return
    }

    pendingRequest = nil
    isCaptureInFlight = true
    captureSequence += 1
    let captureID = captureSequence
    activeCaptureID = captureID
    lastCaptureStart = now

    // A tiny 1×1 HDR screenshot can contain an invalid half-float pixel on
    // some macOS/display combinations. Keep the capture small, but sample a
    // real block and read its center pixel instead.
    let outputSize: CGFloat = 16
    let logicalCaptureSize = outputSize / request.pixelScale
    let localX = request.point.x - request.screen.frame.minX
    let localY = request.screen.frame.height
      - (request.point.y - request.screen.frame.minY)
    let halfSize = logicalCaptureSize / 2
    let sourceX = min(
      max(localX - halfSize, 0),
      max(request.screen.frame.width - logicalCaptureSize, 0)
    )
    let sourceY = min(
      max(localY - halfSize, 0),
      max(request.screen.frame.height - logicalCaptureSize, 0)
    )
    let sourceRect = CGRect(
      x: sourceX,
      y: sourceY,
      width: logicalCaptureSize,
      height: logicalCaptureSize
    )

    let configuration = SCStreamConfiguration(preset: .captureHDRScreenshotLocalDisplay)
    configuration.sourceRect = sourceRect
    configuration.width = Int(outputSize)
    configuration.height = Int(outputSize)
    configuration.colorSpaceName = CGColorSpace.extendedDisplayP3
    configuration.showsCursor = false

    SCScreenshotManager.captureSampleBuffer(
      contentFilter: request.filter,
      configuration: configuration
    ) { [weak self] sampleBuffer, error in
      let color = error == nil
        ? sampleBuffer.flatMap { CMSampleBufferGetImageBuffer($0) }
          .flatMap(PixelSampler.color(from:))
        : nil
      self?.finishCapture(request, color: color, captureID: captureID)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + captureTimeout) { [weak self] in
      guard let self,
            self.isCaptureInFlight,
            self.activeCaptureID == captureID else {
        return
      }
      self.finishCapture(request, color: nil, captureID: captureID)
    }
  }

  @available(macOS 15.0, *)
  private func finishCapture(
    _ request: PendingRequest,
    color: NSColor?,
    captureID: Int
  ) {
    DispatchQueue.main.async {
      guard self.isCaptureInFlight,
            self.activeCaptureID == captureID else {
        return
      }

      self.isCaptureInFlight = false
      self.activeCaptureID = nil
      defer { self.startNextCapture() }

      guard request.generation == self.generation,
            let color else {
        request.completion(nil)
        return
      }

      request.completion(color)
    }
  }
}
