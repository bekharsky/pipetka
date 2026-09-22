# Pipetka

A native macOS color picker app with AI assistant integration.

## Features

### Desktop App

- **Screen Color Picker** - Magnified lens overlay to sample any pixel on screen with precise crosshair targeting
- **Multiple Output Formats** - Copy colors as HEX, RGB, HSL, CSS HDR `color(srgb …)`, or SwiftUI Color syntax
- **HDR Sampling** - On macOS 15+ and Apple Silicon, preserves extended-range screen components instead of clipping them to 8-bit SDR
- **Color Names** - Automatically identifies nearest named color for every pick (1,500+ color database)
- **Pick History** - Persistent history with quick copy, export, and visual swatches
- **Image Palette Extraction** - Import images to extract dominant color palettes (up to 8 colors)
- **Batch Export** - Export palettes and history as CSS Variables, SCSS, Tailwind config, or JSON tokens
- **Menu Bar Integration** - Quick access to recent picks via menu bar item
- **Drag & Drop Support** - Drop images or folders to extract color palettes

### MCP Server (AI Assistant)

Pipetka includes a Model Context Protocol (MCP) server that exposes color picking functionality to AI assistants like Claude and GitHub Copilot:

- **`pick_color`** - Opens the interactive screen picker and returns hex, rgb, hsl, and extendedRGB values with visual swatch and color name
- **`extract_palette`** - Opens file picker to extract dominant colors from images with swatches and names

The MCP server allows AI assistants to help you pick colors and extract palettes directly from conversations. When picking colors, the IDE window automatically hides to give you an unobstructed view of the screen.

## Screenshots

<img width="532" height="612" alt="Screenshot 2026-04-27 at 9 54 07" src="https://github.com/user-attachments/assets/84d55462-6ff0-49db-916a-61a263a0d2e8" />
<img width="532" height="612" alt="Screenshot 2026-04-27 at 9 54 28" src="https://github.com/user-attachments/assets/5e48a29d-3f1a-4151-a9e3-1d3575e84786" />
<img width="532" height="612" alt="Screenshot 2026-04-27 at 9 54 38" src="https://github.com/user-attachments/assets/7723da17-e68c-4c61-b007-dde71c0ffb29" />

## Architecture

The project consists of three main components:

- **Pipetka** - The native macOS app (AppKit + SwiftUI) with the main UI, history management, and screen picker
- **MCPServer** - A Swift stdio-based MCP server that exposes color picking tools to AI assistants
- **PipetkaCore** - Shared Swift package containing core logic used by both Pipetka and MCPServer:
  - Color naming database and lookup
  - Screen color picker implementation
  - Image palette extraction
  - Color utilities and models

## Build

### Desktop App

Build the macOS app to `build/native/Release/`:

```bash
xcodebuild -project Pipetka.xcodeproj -scheme Pipetka -configuration Release SYMROOT="$PWD/build/native" build
```

The project uses the local Apple Development signing identity for the app target. Keep code signing enabled and use the same identity for local rebuilds so macOS Screen Recording permission remains associated with the installed app.

Built app location:

```bash
build/native/Release/Pipetka.app
```

### Install and run the local Release build

The local Release configuration is intentionally not sandboxed. This avoids the macOS sandbox-container consent loop for the locally installed utility. Keep Xcode code signing enabled: do not pass `CODE_SIGNING_ALLOWED=NO`, because that produces an unsigned/ad-hoc bundle that can make TCC permissions appear to reset on every reinstall.

```bash
APP_PATH="$PWD/build/native/Release/Pipetka.app"

xcodebuild \
  -project Pipetka.xcodeproj \
  -scheme Pipetka \
  -configuration Release \
  -sdk macosx \
  CODE_SIGN_IDENTITY="Apple Development" \
  SYMROOT="$PWD/build/native" \
  build

osascript -e "do shell script \"killall Pipetka 2>/dev/null || true; rm -rf /Applications/Pipetka.app; ditto --rsrc --extattr '$APP_PATH' /Applications/Pipetka.app\" with administrator privileges"
open -a /Applications/Pipetka.app
```

Pipetka requests Screen Recording only when `Pick Color` is used, not on app launch. If the permission database needs to be cleared while debugging, reset only this app's entry and then relaunch it:

```bash
tccutil reset ScreenCapture com.kharion.pipetka
killall Pipetka 2>/dev/null || true
open -a /Applications/Pipetka.app
```

While moving the picker, the lens uses the fast SDR sample only. HDR is sampled once on confirmation and preserved in CSS HDR and SwiftUI output. UI swatches and previews use a tone-mapped SDR representation; if the HDR service does not answer promptly or returns an invalid buffer, the picker safely keeps the SDR sample instead of hanging or storing corrupted components.

Update the App Store marketing version:

```bash
./bump-version.sh --patch
```

Xcode Cloud uses `ci_scripts/ci_post_clone.sh` to write `CI_BUILD_NUMBER` into `CURRENT_PROJECT_VERSION`, so the cloud build number is the release source of truth. The local value in `Pipetka/Configs/AppInfo.xcconfig` is only a fallback for local builds.

### MCP Server

Build the MCP server executable:

```bash
cd MCPServer
swift build -c release
```

Built executable:

```bash
MCPServer/.build/release/pipetka-mcp
```

For detailed instructions on distributing and configuring the MCP server for different AI assistants, see [MCP.md](MCP.md).

## Test

Run the unit test suite:

```bash
xcodebuild -project Pipetka.xcodeproj -scheme Pipetka -destination 'platform=macOS' test
```

Tests cover color formatting, export helpers, lens placement logic, image palette extraction, and `PipetkaStore` behavior.

## Notes

- **Screen Recording Permission**: On first use, macOS will prompt for Screen Recording permission to enable the color picker
- **Image Import**: Supports individual image files, multiple selections, and entire folders
- **History Integration**: Colors from imported palettes are automatically added to history for immediate access
- **Color Names**: Powered by a database of 1,500+ named colors for automatic color identification
