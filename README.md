# Force EDID

A small macOS app that **locks the EDID** a Mac uses for an external display. That is the practical way to keep an **ATEN HDMI/DisplayPort extender over point-to-point Ethernet** from dropping the picture.

- **Apple Silicon:** macOS has no System Settings checkbox, and plist overrides are ignored. The app injects a chosen EDID at runtime with Apple’s display coprocessor API (`IOAVServiceSetVirtualEDIDMode`).
- **Intel:** the app writes a display override under `/Library/Displays/Contents/Resources/Overrides/` (administrator password). Unplug and replug the display afterwards. That override persists until you Reset.

It does **not** turn HDCP on or off. Apple still handles HDCP automatically. A stable, complete EDID just stops the Mac and the extender from renegotiating forever.

## Typical ATEN workflow

1. Open the app (download a [release](https://github.com/desertdognl/force-edid/releases), or `./build.sh` then `open "build/Force EDID.app"`).
2. **Best quality lock:** plug the display into the Mac directly, click **Capture current EDID**, then reconnect through the ATEN.
3. Or pick a preset:
   - **1080p60 HDMI** — most reliable on HDMI Cat6 / HDBaseT-class boxes
   - **4K30 HDMI 1.4** — typical ATEN 4K ceiling
   - **4K60 HDMI 2.0** — only if the extender actually carries 18 Gbps
4. Select an external display, pick an EDID, then **Apply to this display**. Use **Apply to all** if every monitor should get the same lock.
5. **Apple Silicon:** leave **Reapply each display after a drop** on, and enable **Open at login** — the inject is lost at reboot. **Intel:** the override file persists until Reset; still unplug/replug once after Apply.

The picture may blink once. That is the link renegotiating with the locked EDID.

If you only have the extender in the path, capture anyway — it is better than nothing — but a direct capture of the real panel is what usually stops the drops.

## What you need

- Apple Silicon (M1–M4) or Intel Mac
- macOS 14 or later
- Xcode Command Line Tools (`xcode-select --install`)
- An EDID file is optional; presets and capture are built in

## Install

Download **Force EDID** from [Releases](https://github.com/desertdognl/force-edid/releases). The zip contains a universal `Force EDID.app` (Apple Silicon and Intel).

The first time you open it, macOS may warn that the app is unsigned. Right-click the app, choose **Open**, then confirm.

## Build from source

```bash
cd "Force Edid"
chmod +x build.sh
./build.sh
open "build/Force EDID.app"
```

The app is **not sandboxed**. Sandboxing would block the display coprocessor calls.

## Command line

The same binary works as a scriptable tool:

```bash
"build/Force EDID.app/Contents/MacOS/ForceEDID" --list
"build/Force EDID.app/Contents/MacOS/ForceEDID" --apply ~/Displays/living-room.bin
"build/Force EDID.app/Contents/MacOS/ForceEDID" --apply ~/Displays/living-room.bin --display "LG UltraFine"
"build/Force EDID.app/Contents/MacOS/ForceEDID" --capture ~/Displays/current.bin --display "LG UltraFine"
"build/Force EDID.app/Contents/MacOS/ForceEDID" --reset
```

Saved EDIDs live in:

`~/Library/Application Support/Force EDID/`

## Hardware notes

- Set the ATEN EDID switch to **Rx** if you want the remote display’s identity, or **Tx** for a local monitor. The app still helps when that switch reports something the Mac will not keep.
- A cheap HDMI EDID emulator between Mac and transmitter is the hardware version of the same idea.
- This uses a **private Apple API** on Apple Silicon. A future macOS update can break it.

## Limits

- **Apple Silicon:** the lock is lost at reboot unless the app reapplies it.
- **Intel:** the override stays until you Reset. Apply needs an administrator password.
- Forcing 4K60 into a 4K30 extender will still drop.
- Apple Silicon uses a **private API**; a future macOS update can break that path.

## Versioning

See [CHANGELOG.md](CHANGELOG.md). The number in the app comes from `Sources/AppInfo.swift`.

Made by [DesertDog](https://desertdog.nl).
