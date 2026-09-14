# Lumen

Native macOS menu bar display manager (SwiftUI, macOS 26). BSquared personal tool.

- Design: `docs/plans/2026-09-14-lumen-design.md`
- Plan: `docs/plans/2026-09-14-lumen-v1.md`

## Commands

- Core tests: `cd Packages/LumenCore && swift test`
- App: `xcodegen generate && xcodebuild -project Lumen.xcodeproj -scheme Lumen -configuration Debug -derivedDataPath build build`
- The `.xcodeproj` is generated, never committed.
