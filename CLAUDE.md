# Lumen

Native macOS menu bar display manager (SwiftUI, macOS 26, Swift 6 strict concurrency).
BSquared personal tool. GitHub: `bsquared-software/lumen` (private).

- Design + hardware findings: `docs/plans/2026-09-14-lumen-design.md`
- v1 plan: `docs/plans/2026-09-14-lumen-v1.md`

## Layout

```
project.yml                      XcodeGen; the .xcodeproj is generated, never committed
Packages/LumenCore/              everything that isn't SwiftUI
  Sources/LumenCore/Model/       DisplayInfo, DisplayMode, Preset, KnownDisplay, hotkey formatting
  Sources/LumenCore/DDC/         DDC/CI packets, DDC-channel-to-display matching
  Sources/LumenCore/Engine/      PresetPlanner, SafetyRules, ModeCatalogue, DisplayWorker, coalescer
  Sources/LumenCore/Store/       state.json persistence, DisplayRegistry merge
  Sources/LumenCore/Backend/     THE ONLY private-API code (SystemDisplayBackend)
  Sources/lumen-probe/           hardware harness (debug only)
  Tests/LumenCoreTests/          Swift Testing + FakeBackend
Lumen/                           SwiftUI app: DisplayController, views, Carbon hotkeys
Lumen/Debug/                     #if DEBUG snapshot hook
scripts/install.sh               Release build → /Applications
```

## Commands

- Core tests: `cd Packages/LumenCore && swift test`
- Debug build: `xcodegen generate && xcodebuild -project Lumen.xcodeproj -scheme Lumen -configuration Debug -derivedDataPath build build`
- Install: `./scripts/install.sh`
- Regenerate the project after adding or removing files in `Lumen/`.

## Rules

- **Private APIs stay in `Backend/`**, resolved with `dlsym` into optional `@convention(c)`
  pointers. A missing symbol must degrade one feature, never crash.
- **Logic goes in LumenCore with tests first.** The app target stays thin. Test hardware
  behaviour through `FakeBackend`, which mimics the real quirks below.
- **Never leave the Mac without a display.** Every disconnect goes through `SafetyRules`
  at the moment it runs, not only at planning time.
- UK English in user-facing copy.

## Hardware facts (M3 Pro, macOS 27, 2026-09-14)

- A disconnected display **vanishes** from `CGGetOnlineDisplayList`. `DisplayRecord` with
  `disconnectedByLumen` is the only handle on it; re-enable uses the remembered display ID.
- Disconnect blocks ~1.3 s; reconnect returns in ~180 ms but the display appears later
  (`waitForOnline` polls up to 5 s).
- Samsung DDC reports brightness max 50; DDC read/write ~60 ms each.
- macOS keeps a separate resolution for the built-in display when it is the only screen
  (1728×1117 with monitors, 2056×1329 alone). That is macOS, not Lumen.

## Testing on the real machine

- `swift run lumen-probe list | modes <uuid> | brightness <uuid> [value] | blink <uuid> <s>`.
  `blink` and brightness writes change Brandon's real displays: warn first, restore after.
- **Never take full-screen screenshots** — the desktop has private content. To see Lumen's
  UI, run the Debug build with `LUMEN_SNAPSHOT_DIR=<dir>` (and optionally
  `LUMEN_OPEN_SETTINGS=1`), read `<dir>/windows.txt`, then capture only that window:
  `screencapture -o -x -l <windowNumber> out.png`. Unfocused windows render prominent
  buttons grey; raise the window first to check highlight states.
- The menu bar item can hide behind the MacBook notch; it is always visible on external
  displays' menu bars.
