# App Launcher

Native macOS app launcher built with SwiftUI + AppKit.

## Requirements

- macOS 14+
- Xcode / Command Line Tools (`swift`, `codesign`)

## Build

From the project root:

```bash
swift build
./scripts/build-app.sh release
```

This creates:

- `build/App Launcher.app`

## Install

Choose one:

```bash
# Install to your user Applications folder and launch
./scripts/install-user-applications.sh
```

or drag `build/App Launcher.app` into `/Applications`.

## Run in development

```bash
swift run AppLauncher
```

