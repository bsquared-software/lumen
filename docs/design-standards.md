# Apple design standards for Lumen

Checked on 2026-09-14 against Apple's Human Interface Guidelines, the macOS 27 and Xcode 27
release notes and the WWDC25/WWDC26 sessions. HIG pages live at
`https://developer.apple.com/design/human-interface-guidelines/<slug>`. Keep new UI inside these
rules; the "In Lumen" column says where each is applied.

| Area | Rule | In Lumen |
|---|---|---|
| Liquid Glass | Standard components adopt glass automatically; remove custom backgrounds; never glass on glass; no glass in the content layer (Adopting Liquid Glass, HIG materials). | No custom backgrounds. Popover buttons stay `.bordered`/`.borderedProminent` because the popover is already glass. |
| Tint | Reserve colour for primary actions or status; one or two prominent buttons per view (HIG color, buttons). | Only the active preset and the login offer's accept button are prominent. |
| Sidebars (27) | Sidebars reach the window edge, selection is semibold, icons use the accent colour; don't restyle (HIG sidebars). | Presets tab is a plain `NavigationSplitView` + `List`. |
| Menu bar extra | Use a template symbol; people decide whether it is shown; a menu-bar-only app quits if the item is removed unless it binds `isInserted` (HIG the-menu-bar, `MenuBarExtra`). | `MenuBarExtra(isInserted:)` + Settings › General "Show Lumen in menu bar"; relaunching opens Settings. |
| Agent app commands | No app menu, so ⌘, and ⌘Q must be reachable (HIG keyboards). | Popover footer: Settings… ⌘,, Quit ⌘Q; About Lumen in Settings › General. |
| Settings window | Toolbar tabs with noun labels; title follows the pane; restore the last pane; size to the pane (HIG settings). | `@AppStorage` tab, per-pane frames. |
| Forms | Consider mini switches in grouped forms (HIG toggles). | Settings switches use `.controlSize(.mini)`. |
| Buttons | Title-style labels starting with a verb; "…" when a button opens another window or needs more input (HIG buttons, menus). | "Save Current Setup as Preset…", "Open Login Items…", "Delete Preset…", "Settings…". |
| Menus (27) | SwiftUI hides menu item icons by default; icons only for objects/concepts, all or none per group; hide unavailable items (release notes, HIG menus, context-menus). | Context menu has no icons and hides Apply while busy; icon picker keeps icons with `.titleAndIcon`. |
| Alerts | Specific title, message as a sentence, a verb button plus Cancel; no destructive style for an action the person deliberately chose (HIG alerts). | "Delete “Night”?" with Delete + Cancel, not styled destructive. |
| Tooltips | Start with a verb, sentence case, don't repeat the control name, 60–75 characters; sliders show their value (HIG offering-help, sliders). | All `.help` strings follow this; sliders read "Adjust brightness (38%)". |
| Empty states | Give a clear next step (HIG writing). | "No Preset Selected" offers Add Preset from Current Setup. |
| Colour | Never convey meaning by colour alone; prefer system colours (HIG accessibility, color). | Warnings and errors carry a symbol; the active preset gains a checkmark with Differentiate Without Color. |
| VoiceOver | Label every control even when the label is hidden; sliders announce value; selected state as a trait; group cards with `.contain` (HIG voiceover, WWDC26 220). | Verified with an accessibility dump: cards, switches, sliders ("Brightness, Odyssey G81SF", "38%"), pickers, `.isSelected` on the active preset, spoken shortcuts. |
| Motion | Symbol effects sparingly, for state changes (HIG sf-symbols, motion). | Menu bar icon uses a replace transition when the active preset changes. |
| App icon | Layered Icon Composer `.icon`, masked by the system; legacy icons get a system background (HIG app-icons, WWDC25 220). | `Icon/AppIcon.icon` (gradient, display, glass sun), wired via `ASSETCATALOG_COMPILER_APPICON_NAME`. |
| Login items | Opt-in only, handle approval (App Review 2.4.5, HIG privacy). | One-time offer in the popover plus a Settings toggle; `requiresApproval` opens Login Items. |

**Not verified on hardware:** Reduce Transparency, Increase Contrast, Show Borders and the macOS 27
Liquid Glass slider, because testing them changes system-wide settings. Everything uses system
controls and colours, so they adapt automatically. VoiceOver pronunciation of "Hz" is unchecked.
