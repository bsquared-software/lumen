# Lumen

A native macOS menu bar app for the displays on a MacBook. It does the parts of
BetterDisplay that get used every day, in a friendlier UI:

- **Switch monitors on and off.** "Off" disconnects the display from macOS, so windows move
  to the screens that stay on and the monitor sleeps from no signal.
- **Brightness** for the built-in display and for external monitors over DDC.
- **Resolution, refresh rate and HiDPI** from every mode macOS offers.
- **Presets** such as *Night* (monitors off, MacBook at 10%) and *Day*, applied from the menu
  or a global shortcut.

## Install

Requires macOS 26, Xcode 26 and XcodeGen (`brew install xcodegen`).

```sh
./scripts/install.sh
```

This builds a Release copy, installs it into `/Applications` and opens it. Turn on
**Open Lumen at login** in Settings › General.

Quit BetterDisplay (or turn off its display connection features) while using Lumen, so the
two apps don't fight over the same displays.

## Using it

Click the sun in the menu bar. Each display gets a card with an on/off switch, a brightness
slider and resolution menus. Presets sit at the top.

| Shortcut | Preset |
|---|---|
| ⌃⌥⌘N | Night: external monitors off, built-in display at 10% |
| ⌃⌥⌘D | Day: everything on, built-in display at the brightness it had on first launch |

Night and Day are created from the displays attached the first time Lumen runs. Edit them,
record new shortcuts or add presets in **Settings › Presets**. **Update from Current Setup**
copies how your displays are set up right now into a preset.

Lumen never switches off the last display that is on. If a monitor won't come back, use
**Reconnect All**, or unplug and replug its cable.

## How it works

Lumen uses private macOS interfaces, so it can't be sandboxed or sold on the App Store, and a
macOS update can break a feature until Lumen is updated:

| Feature | Interface |
|---|---|
| On / off | `CGSConfigureDisplayEnabled` (SkyLight) |
| Built-in brightness | `DisplayServicesSetBrightness` |
| Monitor brightness | DDC/CI over `IOAVService` (`DCPAVServiceProxy`) |
| Resolution | `CGConfigureDisplayWithDisplayMode` (public) |
| Shortcuts | Carbon `RegisterEventHotKey` (public, no Accessibility permission) |

Settings live in `~/Library/Application Support/Lumen/state.json`.

## Development

```sh
cd Packages/LumenCore && swift test      # core logic, no Xcode needed
xcodegen generate && open Lumen.xcodeproj
```

The design and the plan it was built from are in `docs/plans/`.
