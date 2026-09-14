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

Click Lumen's icon in the menu bar: a sun, or the icon of the preset you applied last. Each
display gets a card, left to right as your displays are arranged, with an on/off switch,
brightness and contrast sliders (contrast where the monitor supports it) and resolution menus.
Presets sit at the top. Launching Lumen again from Spotlight opens Settings.

| Shortcut | Preset |
|---|---|
| ⌃⌥⌘N | Night: external monitors off, built-in display at 10% |
| ⌃⌥⌘D | Day: everything on, built-in display at the brightness it had on first launch |

Night and Day are created from the displays attached the first time Lumen runs.

- **Save a preset** from the popover's save button, or with **+** in **Settings › Presets**.
  **Update from Current Setup** copies how your displays are set up right now into a preset,
  keeping displays that aren't plugged in.
- **Edit presets** in Settings: name, icon, shortcut, and what each display should do. Drag
  presets to change their order in the popover.
- **Rename displays** in **Settings › Displays**, e.g. "Left OLED" instead of "Odyssey G81SF".
- Resolution menus show the sizes worth picking, like System Settings does. The mode in use
  always stays listed.

Lumen never switches off the last display that is on. If a monitor won't come back, use
**Reconnect All**, or unplug and replug its cable.

## Preset links

Every preset has a link, shown and copyable in Settings:

```sh
open "lumen://apply/Night"
open "lumen://apply/Night%20Mode"   # names with spaces are URL-encoded
```

Use them from Shortcuts (Open URLs), Raycast, a Stream Deck, or a scheduled job to switch
presets at set times. Names match without regard to case.

## How it works

Lumen uses private macOS interfaces, so it can't be sandboxed or sold on the App Store, and a
macOS update can break a feature until Lumen is updated:

| Feature | Interface |
|---|---|
| On / off | `CGSConfigureDisplayEnabled` (SkyLight) |
| Built-in brightness | `DisplayServicesSetBrightness` |
| Monitor brightness | DDC/CI over `IOAVService` (`DCPAVServiceProxy`) |
| Monitor contrast | DDC/CI over `IOAVService` |
| Resolution | `CGConfigureDisplayWithDisplayMode` (public) |
| Shortcuts | Carbon `RegisterEventHotKey` (public, no Accessibility permission) |

Settings live in `~/Library/Application Support/Lumen/state.json`.

## Development

```sh
cd Packages/LumenCore && swift test      # core logic, no Xcode needed
xcodegen generate && open Lumen.xcodeproj
```

The design and the plan it was built from are in `docs/plans/`.
