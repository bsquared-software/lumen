# Lumen — design

**Date:** 2026-09-14 · **Status:** agreed, building v1

A native macOS menu bar app for Brandon's MacBook Pro (M3 Pro) and its two external
monitors. It clones the parts of BetterDisplay Pro that actually get used, in a
friendlier UI, and is the base for more display features later.

## The job

The night routine is the reason this exists: switch both external monitors **off** and
leave the MacBook on its built-in display at **10% brightness**, in one click or one
hotkey. The morning routine is the reverse.

## Scope

**In v1**

| Feature | Detail |
|---|---|
| Connect / disconnect | Per-display on/off. "Off" means macOS stops driving the display: windows move to the remaining displays and the panel sleeps from no signal. |
| Brightness | Built-in display via DisplayServices. External monitors via DDC/CI (VCP `0x10`). |
| Resolution / refresh / HiDPI | Every mode macOS offers, including the HiDPI duplicates, grouped by resolution with a refresh-rate choice. |
| Presets | Named snapshots of every display's state. "Save current as preset". Apply from the menu or a global hotkey. Night and Day ship preconfigured. |
| Launch at login | `SMAppService.mainApp`. |

**Not in v1:** schedules / sunset triggers, custom resolutions macOS does not offer
(BetterDisplay's virtual-display HiDPI trick), a CLI, colour profiles, rotation.

**Added after v1 (2026-09-14, two quick-win passes):** `lumen://apply/<preset>` and
`lumen://reconnect-all` links (the answer to scheduling: Shortcuts or `open` from a scheduled
job), display renaming and forgetting, DDC contrast, desk-order cards, a first-run
open-at-login offer, reconnect-on-quit, preset duplication and display add/remove, a shorter
resolution list, the active preset surviving a relaunch, and popover keyboard shortcuts.
Still out: in-app schedules, Night Shift / True Tone in presets, contrast in presets.

## Hardware (verified 2026-09-14, macOS 27.0)

| Display | CG id | Vendor / model / serial | Port | DDC brightness |
|---|---|---|---|---|
| Built-in Liquid Retina XDR | 1 | 1552 / 41040 / 4251086178 | `disp0` | n/a (DisplayServices) |
| Samsung LS32D70xE | 3 | 19501 / 30291 / 809582919 | `dispext0` | answers, max 50 |
| Samsung Odyssey G81SF | 2 | 19501 / 30540 / 811091798 | `dispext1` | answers, max 50 |

Every private symbol below resolved via `dlsym` on this machine. A read-only DDC
"Get VCP 0x10" query succeeded on both Samsungs at the first attempt.

## Approach

**Native Swift calling the display APIs directly** (chosen). The alternatives were a
SwiftUI shell over `displayplacer` + `m1ddc` (a process spawn per slider tick, text
parsing, Homebrew dependencies) and public APIs only (not viable: macOS has no public
way to disconnect a display).

Consequences we accept: no App Store, no sandbox, and a macOS update can break a private
call. Every private call is isolated behind one protocol so a break is contained to one
file.

## System APIs

| Capability | API | Public? |
|---|---|---|
| Enumerate displays | `CGGetOnlineDisplayList`, `CGDisplayVendorNumber/ModelNumber/SerialNumber`, `CGDisplayCreateUUIDFromDisplayID` (ColorSync) | yes |
| Connect / disconnect | `CGSConfigureDisplayEnabled(config, id, enabled)` inside `CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration` | **private** |
| Built-in brightness | `DisplayServicesGetBrightness` / `DisplayServicesSetBrightness` | **private** |
| External brightness | `IOAVServiceCreateWithService` + `IOAVServiceWriteI2C` / `IOAVServiceReadI2C` on `DCPAVServiceProxy` nodes (chip `0x37`, address `0x51`) | **private** |
| Modes | `CGDisplayCopyAllDisplayModes` with `kCGDisplayShowDuplicateLowResolutionModes`, `CGConfigureDisplayWithDisplayMode` | yes |
| Hotplug | `CGDisplayRegisterReconfigurationCallback` | yes |
| Hotkeys | Carbon `RegisterEventHotKey` | yes (no dependency, no Accessibility permission) |
| Launch at login | `SMAppService.mainApp` | yes |

### DDC/CI wire format

- **Get VCP:** write `[0x82, 0x01, vcp, chk]` where `chk = 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ vcp`,
  wait ~50 ms, read 11 bytes.
- **Reply:** `[0x6E, 0x88, 0x02, result, vcp, type, maxHi, maxLo, curHi, curLo, chk]`,
  valid when `result == 0`, `vcp` echoes, and `chk == 0x50 ^ xor(bytes[0...9])`
  (checked against both real replies).
- **Set VCP:** write `[0x84, 0x03, vcp, hi, lo, chk]` where
  `chk = 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ vcp ^ hi ^ lo`.

Samsung reports max 50, so brightness is always normalised to `0...1` using the
reported max.

### Matching a DDC channel to a display

Each external `DCPAVServiceProxy`'s registry path contains its port (`dispext0:dcpav-service-epic`).
The `IOMobileFramebufferShim` under `dispext0@…` carries
`DisplayAttributes.ProductAttributes` with `LegacyManufacturerID`, `ProductID` and
`SerialNumber`, which equal the CoreGraphics vendor, model and serial. Match on all three;
fall back to vendor + model when exactly one candidate remains. This is pure logic and is
unit-tested.

## Architecture

```
lumen/
  project.yml                 XcodeGen (the .xcodeproj is generated, not committed)
  Packages/LumenCore/         SwiftPM package, `swift test` runs without Xcode
    Sources/LumenCore/
      Model/                  DisplayInfo, DisplayState, DisplayMode, Preset, Brightness
      Engine/                 PresetPlanner (pure), SafetyRules (pure), ModeCatalogue (pure)
      DDC/                    DDCPacket encode/decode (pure), AVServiceMatcher (pure)
      Backend/                DisplayBackend protocol + SystemDisplayBackend (the only
                              file set that touches private APIs)
      Store/                  JSON persistence for presets and known displays
    Tests/LumenCoreTests/     Swift Testing, fake backend
  Lumen/                      SwiftUI app target
    LumenApp.swift            MenuBarExtra(.window) + Settings scene, LSUIElement
    DisplayController.swift   @Observable, owns backend + stores, serialises work
    Views/                    MenuContent, DisplayCard, PresetBar, Settings/*
    Hotkeys/                  Carbon hotkey registration + shortcut recorder
```

`DisplayBackend` is the seam:

```swift
protocol DisplayBackend: Sendable {
    func onlineDisplays() -> [DisplayInfo]
    func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) throws
    func brightness(of display: DisplayInfo) throws -> Double
    func setBrightness(_ value: Double, of display: DisplayInfo) throws
    func modes(of displayID: CGDirectDisplayID) -> [DisplayMode]
    func currentMode(of displayID: CGDirectDisplayID) -> DisplayMode?
    func setMode(_ mode: DisplayMode, displayID: CGDirectDisplayID) throws
}
```

## Identity and remembered displays

A disconnected display vanishes from `CGGetOnlineDisplayList`, and re-enabling it needs
its `CGDirectDisplayID`. Lumen therefore keeps `known-displays.json`: UUID, name, vendor,
model, serial, built-in flag, last known display ID, and whether Lumen disconnected it.
The menu lists known-but-offline displays with their switch off, so they can always be
switched back on, including after the app restarts.

Disconnects are applied with `.forSession`, so a logout or reboot should always bring every
monitor back even if Lumen is gone (not yet observed across a logout).

**Hardware findings (2026-09-14, `lumen-probe blink` on the LS32D70xE):**

- A disconnected display **vanishes from `CGGetOnlineDisplayList` entirely**; it is not
  reported as online-but-inactive. The saved record is the only handle on it.
- Re-enabling with the remembered `CGDirectDisplayID` works. The display returned with the
  **same ID (3)**, the same HiDPI mode and the same DDC brightness.
- `CGSConfigureDisplayEnabled(false)` blocks for **~1.3 s** (macOS moves windows before
  returning). Re-enabling returns in **~180 ms** but the display takes a further moment to
  appear, so presets poll for it (`waitForOnline`, up to 5 s).
- DDC brightness read and write each take **~60 ms**; DisplayServices takes ~1 ms.
- While a display is switched off, its `IOMobileFramebufferShim` **stays in the IORegistry**
  with the same `ProductAttributes` (checked during a second `blink`). Lumen uses this to tell
  "switched off" from "unplugged": a flagged record with no matching framebuffer is
  unavailable. Not yet observed: the registry after physically unplugging a monitor.
- DDC reads to the *other* monitor can fail transiently while a display is being
  reconfigured, so Lumen refreshes again once the change settles.
- `CGDisplayIsActive` is not used: switched-off displays leave the online list entirely, and
  the flag is also false for sleeping displays.

## Safety rules (pure, unit-tested)

1. Never disconnect the last active display. A preset or toggle that would do so is
   refused with a message.
2. Applying a preset runs in a fixed order: **connect** displays that should be on →
   wait for them to come online → set **modes** → set **brightness** → **disconnect**
   displays that should be off. The built-in is never disconnected by a preset.
3. A preset entry for a display that is not attached is skipped and reported, never
   fatal.
4. "Reconnect all" is always present in the menu.

## Presets

```json
{ "id": "…", "name": "Night", "hotkey": { "keyCode": 45, "modifiers": ["control","option","command"] },
  "displays": [
    { "uuid": "11F14D77-…", "name": "Odyssey G81SF", "connected": false },
    { "uuid": "E292FE42-…", "name": "LS32D70xE",     "connected": false },
    { "uuid": "37D8832A-…", "name": "Built-in",      "connected": true, "brightness": 0.10 }
  ] }
```

Each field other than `uuid` and `connected` is optional: an absent field means "leave as
is". "Save current as preset" captures connection, brightness and mode for every display.
Night and Day are seeded on first launch from the displays attached at that moment.

## UI

- **Menu bar icon:** SF Symbol `sun.max`; `moon` while the active preset is Night.
- **Popover** (`MenuBarExtra`, `.window` style): preset buttons along the top, one card
  per display (name + icon, on/off switch, brightness slider, resolution menu with
  refresh submenu), then Reconnect all / Settings / Quit.
- **Settings window:** Presets (list, rename, edit per-display values, record hotkey,
  delete), General (launch at login).
- Native macOS 26 components throughout. Glass only on the navigation layer, never on
  content; no hand-rolled buttons.

## Reliability

- DDC is slow and occasionally drops a packet: writes go through a per-display serial
  queue, slider changes are coalesced (latest value wins), each write retries up to 3
  times with a short delay, and reads validate the checksum.
- Display reconfiguration callbacks refresh the model; the UI never caches a display ID
  across a reconfiguration.
- Errors surface inline on the relevant card, not as alerts.

## Testing

- **Unit (Swift Testing, `swift test`):** DDC encode/decode against the two real replies,
  AV-service matching, mode grouping/dedupe, preset planning order, the last-display rule,
  missing-display skips, store round-trips.
- **Hardware (manual, scripted):** a debug harness disconnects one external monitor and
  reconnects it after 5 s; brightness round-trips on all three displays; Night then Day
  applied from the app.
