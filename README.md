# Touchdown

A macOS driver that converts touch input from the Corsair Xeneon Edge (14.5" touch bar, 2560x720) into mouse clicks at the correct absolute screen position.

Without it, macOS ignores the panel's HID digitizer interface (usage page `0x0D`, usage `0x04`) entirely and falls back to its Generic Desktop Mouse interface, which it reads as *relative* deltas. A tap becomes "click wherever the cursor already is" instead of "click here."

> Fork of [ymlaine/TouchscreenDriver](https://github.com/ymlaine/TouchscreenDriver), originally co-authored by [Yves-Marie Lainé](https://github.com/ymlaine) and Claude.

## What this fork changes

**Installs as a signed `.app` bundle, not a bare binary.** macOS TCC will not register a raw Mach-O executable for Accessibility — it never appears in the Privacy & Security list, so the permission can't be granted and clicks can never be injected. `tccutil reset Accessibility` on the installed binary confirms it: *"No such bundle identifier."* There was no record to toggle. Only a code-signed bundle with a `CFBundleIdentifier` gets a TCC record.

**No more permission-dialog storm.** Upstream calls `AXIsProcessTrustedWithOptions` with `prompt: true` and then `exit(1)` when the grant is missing. Combined with the LaunchAgent's `KeepAlive { SuccessfulExit = false }`, launchd relaunches on every failure and each launch throws a fresh dialog — an unbounded loop of stacked prompts. This fork prompts once, then polls `AXIsProcessTrusted()` silently every 2s and proceeds the moment you grant it. No relaunch, no second dialog, no restart needed.

**No sudo.** Installs to `~/Applications` and `~/Library/LaunchAgents` instead of `/usr/local/bin`, which is root-owned. Nothing root-owned to clean up.

**A menu bar icon** (`hand.rays`), so the driver's state is visible instead of log-only. Upstream runs completely invisibly — if it's stuck waiting on a permission or can't find the panel, there's no way to tell without `tail`ing a file in `/tmp`. The icon dims while waiting, goes solid when active, and turns red on failure. Its menu shows the target display and offers redetect / open log / quit.

**Survives failure instead of exiting.** Upstream calls `exit(1)` when the HID open is refused or the panel isn't found — which, under `KeepAlive`, is the same relaunch-loop trap as the permission bug. This fork reports the failure in the menu bar and stays up; a missing panel retries every 3s, so unplugging and replugging the Xeneon just works.

**`LSUIElement`** plus `.accessory` activation policy so it stays out of the Dock and ⌘-Tab, and `uninstall.sh` clears the TCC records so a later reinstall prompts cleanly.

Note: the ad-hoc signature is hash-based, so **recompiling voids both permission grants** and you'll re-approve.

## Menu bar

| Icon | Meaning |
|---|---|
| Dimmed | Waiting on Accessibility permission, or waiting for the panel to appear |
| Solid | Active — taps are being mapped to clicks |
| Red | HID open refused (usually Input Monitoring missing, or another app holds the device) |

## Features

- Converts touch events to mouse clicks at the touched position
- Exclusive HID capture (no double clicks)
- Multi-monitor support with automatic screen detection
- Cursor returns to original position after click
- Adapts to resolution changes (including HiDPI/scaled modes)
- Dynamic reconfiguration when displays are rearranged

## How It Works

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Touchscreen    │────▶│  Driver          │────▶│  macOS          │
│  (USB HID)      │     │  (exclusive)     │     │  (CGEvent)      │
└─────────────────┘     └──────────────────┘     └─────────────────┘
   Raw X, Y coords        Convert & map          Click at absolute
   Button events          to screen space        position
```

## Requirements

- macOS 10.15+ (Catalina or later)
- Xcode Command Line Tools: `xcode-select --install`
- Corsair Xeneon Edge connected via USB-C

## Installation

### Automatic (Recommended)

```bash
git clone https://github.com/bencolson/Touchdown.git
cd Touchdown
./install.sh
```

This will:
- Compile the driver
- Package and ad-hoc sign `~/Applications/Touchdown.app`
- Install a LaunchAgent so it starts at login
- Start it immediately (no sudo at any point)

### Uninstall

```bash
./uninstall.sh
```

### Manual

```bash
git clone https://github.com/bencolson/Touchdown.git
cd Touchdown
chmod +x run_driver.sh run_analyzer.sh
./run_driver.sh
```

### Grant Permissions

Grant both to **`Touchdown.app`** — not to Terminal, and not to a bare binary:

1. **Accessibility** — to inject mouse clicks
   - System Settings → Privacy & Security → Accessibility
2. **Input Monitoring** — to capture HID events (exclusive seize)
   - System Settings → Privacy & Security → Input Monitoring

The driver waits for the grant and continues within 2 seconds. You do not need to restart it.

If the app doesn't appear in the list, drag `~/Applications/Touchdown.app` in directly.

### Control Commands

```bash
# Status
pgrep -f Touchdown && echo "Running" || echo "Stopped"

# Logs
tail -f /tmp/touchdown.log

# Stop
launchctl unload ~/Library/LaunchAgents/com.bencolson.touchdown.plist

# Start
launchctl load ~/Library/LaunchAgents/com.bencolson.touchdown.plist
```

## Calibration

The driver is pre-calibrated for the Xeneon Edge touchscreen:
- X range: 0 - 16383
- Y range: 0 - 9599
- Touch detection: Button 1 (HID Usage Page 0x09)

### Re-calibrate (if needed)

If touch positions are incorrect, use the analyzer:

```bash
./run_analyzer.sh
```

Touch the screen corners and note the X/Y max values, then update `TouchscreenDriver.swift`:

```swift
var touchscreenMaxX: CGFloat = 16383  // Your X max
var touchscreenMaxY: CGFloat = 9599   // Your Y max
```

## Hardware Info

```
Touchscreen Controller:
  Vendor ID:  0x27c0
  Product ID: 0x0859
  Manufacturer: wch.cn

Display:
  Native resolution: 2560x720 (32:9 ratio)
  Recommended: 1920x540 scaled (better readability)
```

## Files

| File | Description |
|------|-------------|
| `TouchscreenDriver.swift` | Main driver with HID capture and CGEvent injection |
| `HIDAnalyzer.swift` | Diagnostic tool to inspect raw HID reports |
| `run_driver.sh` | Build and run the driver |
| `run_analyzer.sh` | Build and run the analyzer |

## Troubleshooting

### "Touchscreen not found"
- Ensure the Xeneon Edge is connected via USB-C
- Check USB connection in System Information → USB
- Verify Vendor/Product IDs match

### "Cannot open IOHIDManager"
- Grant Input Monitoring permission to Terminal
- Restart Terminal after granting permissions
- Close other apps using the touchscreen (iCUE, etc.)

### Clicks at wrong position
1. Run `./run_analyzer.sh` and touch screen corners
2. Update touchscreenMaxX/Y values in the code
3. Rebuild with `./run_driver.sh`

### Exclusive mode fails
Another app may be using the touchscreen. Either:
- Close conflicting apps (iCUE, etc.)
- Switch to shared mode (edit `TouchscreenDriver.swift`):
  ```swift
  var captureMode: CaptureMode = .shared
  ```
  Note: Shared mode may cause double clicks.

## Resolution Tips

The native 2560x720 resolution can make text hard to read. For better readability:

1. Go to **System Settings → Displays**
2. Select the Xeneon Edge
3. Choose **1920x540** (maintains 32:9 ratio, larger text)

The driver automatically adapts to any resolution.

## License

MIT License - Feel free to use and modify.

## Credits

Created by **Yves-Marie Lainé** in collaboration with **Claude** (Anthropic).

Built with Swift using IOKit HID and CoreGraphics frameworks.
