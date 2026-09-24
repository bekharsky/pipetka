# Pipetka

A native macOS color picker app with AI assistant integration.

## Features

### Desktop App

- **Screen Color Picker** - Magnified lens overlay to sample any pixel on screen with precise crosshair targeting
- **Multiple Output Formats** - CSS HDR with OKLCH is the default; copy colors as HEX, RGB, HSL, CSS Color profiles (`sRGB`, Display P3, Rec. 2020, Rec. 2100 PQ/HLG/Linear), or SwiftUI Color syntax
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

The local `Release` configuration is intentionally not sandboxed. It is the configuration for our local/GitHub non-App-Store build and avoids the macOS sandbox-container consent loop for the installed utility. Keep Xcode code signing enabled: do not pass `CODE_SIGNING_ALLOWED=NO`, because that produces an unsigned/ad-hoc bundle that can make TCC permissions appear to reset on every reinstall.

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

Pipetka requests Screen Recording only when `Pick Color` is used, not on app launch. The first `Pick Color` shows the macOS system request. If it is denied, Pipetka returns to the app without opening a second dialog; a subsequent `Pick Color` shows Pipetka's own explanation and System Settings shortcut without repeating the system request. If the permission database needs to be cleared while debugging, reset only this app's entry and then relaunch it:

```bash
tccutil reset ScreenCapture com.kharion.pipetka
killall Pipetka 2>/dev/null || true
open -a /Applications/Pipetka.app
```

#### Reusing the local TCC/signing setup in another macOS utility

macOS TCC associates Screen Recording permission with the app's code requirement, not only its bundle identifier. An unsigned/ad-hoc build (`CODE_SIGN_IDENTITY = "-"` or `CODE_SIGNING_ALLOWED=NO`) can therefore look like a new app after every rebuild. A sandboxed local utility can also trigger a separate container-consent loop.

For a locally installed, non-App-Store utility, keep these settings stable:

- `PRODUCT_BUNDLE_IDENTIFIER` stays unchanged between installs.
- `DEVELOPMENT_TEAM` points to the same team.
- `CODE_SIGN_STYLE = Automatic` and `CODE_SIGN_IDENTITY = "Apple Development"`.
- Release uses `ENABLE_APP_SANDBOX = NO` and an empty/non-sandboxed Release entitlements file.
- Build with signing enabled (`CODE_SIGNING_ALLOWED=YES`, or simply omit the override).

Verify the result before installing:

```bash
codesign --verify --deep --strict build/native/Release/Pipetka.app
codesign -dv --verbose=4 build/native/Release/Pipetka.app 2>&1 \
  | rg 'Identifier|TeamIdentifier|Authority|flags'
```

This recipe is for local development builds. App Store or Developer ID distribution should use its own distribution identity and the entitlements required by that distribution channel.

### App Store / Xcode Cloud build

The shared `Pipetka` scheme archives with the `AppStore` configuration. This configuration enables App Sandbox and uses `Pipetka/AppStore.entitlements`, which grants only the sandbox and read-only access to files explicitly selected by the user. Xcode Cloud should archive the shared `Pipetka` scheme without overriding its Archive configuration; it will then use the App Store signing and provisioning managed by Xcode Cloud.

To validate the App Store configuration locally without installing it over the non-sandboxed utility:

```bash
xcodebuild \
  -project Pipetka.xcodeproj \
  -scheme Pipetka \
  -configuration AppStore \
  -sdk macosx \
  CODE_SIGN_IDENTITY="Apple Development" \
  SYMROOT="$PWD/build/appstore" \
  build

codesign --verify --deep --strict build/appstore/AppStore/Pipetka.app
codesign --display --entitlements :- build/appstore/AppStore/Pipetka.app
```

The output of the last command must contain `com.apple.security.app-sandbox` with a true value. Use the ordinary `Release` configuration for the local/GitHub build; use `AppStore` only for the App Store archive.

### GitHub Release build

GitHub Releases use the ordinary non-sandboxed `Release` configuration, with Hardened Runtime enabled, signed with `Developer ID Application`, and notarized before publishing. This keeps the downloaded utility separate from the App Store sandbox while still giving macOS a stable, verifiable code signature. The workflow runs on the pinned `xcode-27` runner so compiler-gated macOS 27 controls are included in the signed binary. It runs for `v*` tags or can be started manually with a version.

Add these repository Actions secrets before using `.github/workflows/release.yml`:

- `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` — base64-encoded Developer ID Application `.p12` certificate.
- `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` — password for that `.p12` file.
- `APPLE_NOTARY_KEY_ID` — App Store Connect API key ID.
- `APPLE_NOTARY_ISSUER_ID` — App Store Connect API issuer ID.
- `APPLE_NOTARY_PRIVATE_KEY_BASE64` — base64-encoded `.p8` private key for the notary API key.

The workflow deliberately fails when these credentials are missing; it must not silently fall back to an unsigned/ad-hoc release. The App Store build does not reuse this workflow: Xcode Cloud archives the shared `Pipetka` scheme with its `AppStore` Archive configuration.

The GitHub Release workflow is intentionally independent from the App Store build: it runs only for `v*` tags (or a manually started workflow). The normal GitHub release flow is:

1. On `main`, bump `MARKETING_VERSION` with `./bump-version.sh --patch` (or `--minor`/`--major`), commit it, and push `main`.
2. Create and push a matching tag from `main`:

   ```bash
   git switch main
   git pull --ff-only origin main
   git tag -a v1.0.13 -m "Release 1.0.13"
   git push origin v1.0.13
   ```

3. GitHub Actions builds, notarizes, and publishes the GitHub Release for that tag.

Xcode Cloud should use a separate workflow whose start condition is a branch change on `release`. Disable its start conditions for `main` and pull requests if App Store builds should not run during ordinary development. Keep GitHub Actions workflow files on `main`; the `release` branch is for Xcode Cloud only. To make an App Store build, merge the desired `main` state into `release` and push `release`; that push starts Xcode Cloud only and does not start the GitHub Release workflow.

For non-release builds, run the manually triggered `SDK Builds` workflow. It builds both modern variants in parallel and uploads two unsigned ZIPs as Actions artifacts without creating a GitHub Release:

- `macos-26` — macOS 26 / Xcode 26 SDK, with a macOS 13 deployment target (and therefore support for macOS 15).
- `xcode-27` — macOS 27 / Xcode 27 SDK, with a macOS 13 deployment target (and therefore support for macOS 15) plus the native macOS 27 tab picker.

Both artifacts are universal (`arm64` and `x86_64`) and can run on macOS 15 or newer. The `xcode-27` runner is selected explicitly instead of using a moving `macos-latest` label, so the modern artifact stays tied to the macOS 27 toolchain.

While moving the picker, the lens uses the fast SDR sample only. HDR is sampled once on confirmation and preserved in CSS profile and SwiftUI output. The CSS profile selector can emit extended sRGB, Display P3, Rec. 2020, or Rec. 2100 PQ/HLG/Linear. Components below 0 or above 1 are valid extended-range/out-of-gamut values in the linear and wide-gamut forms; PQ and HLG encode into their nominal display range. After confirmation, history swatches keep the HDR color when the display supports it, while HEX/RGB/HSL show a tone-mapped SDR approximation marked as `HDR`. If the HDR service does not answer promptly or returns an invalid buffer, the picker safely keeps the SDR sample instead of hanging or storing corrupted components.

The output format row uses the standard SwiftUI tab picker on macOS 27 and a segmented picker fallback on earlier supported systems. The CSS tab is labeled with the selected profile (for example, `OKLCH` or `P3`), while the seven profiles remain available from the compact menu beside the history actions. System controls adopt the current macOS Liquid Glass appearance automatically.

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
