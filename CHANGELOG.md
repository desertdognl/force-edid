# Changelog

All notable changes to Force EDID are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Bump `AppInfo.version` and `AppInfo.build` in `Sources/AppInfo.swift` for every release,
add an entry here, then run `./build.sh`.

## [1.2.1] - 2026-09-10

### Added

- Native macOS app icon, the same display-and-arrow mark as in the header.

### Changed

- Smaller, centered window (840×560) so it no longer sticks to the top of the screen.
- Compact header: icon, **v1.2.1**, and a clear **Made by DesertDog** link.

## [1.2.0] - 2026-09-10

### Fixed

- Freeze with no external display. A process sample showed **2.2 GB RAM** and 100% SwiftUI (`MenuBarExtra` / layout), and **zero** display-coprocessor / EDID calls. The app was not sending EDID to a missing screen.
- Removed SwiftUI `MenuBarExtra` (that scene graph looped). Menu bar is now a one-shot AppKit status item after the window is up.
- Apply / Reset / Capture now refuse before any DCP call if no external `NSScreen` is present.

## [1.1.5] - 2026-09-10

### Changed

- Restored the original window layout: version badge, DesertDog credit, Apple Silicon badge, drop-seconds setting, menu bar extra, and login toggle — without the unbounded frames that froze SwiftUI.

## [1.1.4] - 2026-09-10

### Fixed

- Immediate freeze at launch. SwiftUI was stuck in an infinite layout loop (`fileExporter` rebuilt the EDID document on every frame, nested `frame(maxWidth: .infinity)` never finished `sizeThatFits`, and `body` re-read EDID files from disk). Layout is now bounded; import/export use standard file panels; EDID details are cached.

## [1.1.3] - 2026-09-10

### Added

- Setting: reapply automatically after the display has been gone for 1–30 seconds (default 3).

### Fixed

- Startup hang: the window no longer waits on screen listing, login items, menu bar extra, or display-change notifications. Those run after the UI is on screen.

## [1.1.2] - 2026-09-10

### Fixed

- Beachball with no external monitor. Launch was calling `CGDisplayIsBuiltin`, which talks to WindowServer/DCP even when nothing is plugged in. The window now opens first; the display list uses screen names only.

## [1.1.1] - 2026-09-10

### Fixed

- Launch no longer talks to the display coprocessor in a loop. That was wedging DCP and making the whole Mac beachball.
- Display list and drop detection use `NSScreen` only.
- `IOAVService` is called once, when you Apply, Capture, or Reset — never on a timer.

## [1.1.0] - 2026-09-10

### Added

- **1920x1080 @ 50** as the default library EDID (CEA 1080p50). Presets are resynced from the app on every launch so new ones show up.
- Version number shown in the app, menu bar, and CLI.
- Credit: made by [DesertDog](https://desertdog.nl).
- This changelog and semantic versioning.
- Reapply the last EDID automatically when the external display has been gone longer than a set number of seconds, so you do not need the screen to click Apply after an ATEN drop.

### Changed

- 50 Hz presets no longer advertise 1080p60 standard timings, so macOS is less likely to jump back to 60 Hz.

## [1.0.0] - 2026-09-10

### Added

- First release: choose, capture, import, and inject an EDID on Apple Silicon.
- Built-in presets for 720p60, 1080p60, 1440p60, 4K30, and 4K60.
- Reset to the display’s factory EDID.
- Menu bar extra, open at login, and reapply after launch.
- Command-line interface (`--list`, `--apply`, `--reset`, `--capture`).
