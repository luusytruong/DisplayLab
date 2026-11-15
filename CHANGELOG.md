# Changelog

## 1.1.0 — 2026-11-16

- English UI (development language) with Vietnamese translation; follows the macOS language.
- Menu bar icon redrawn from the app icon design (monochrome template, 18 pt tall).
- Panel header shows the app icon; app icon shadow no longer gets cut off at the canvas edge.
- Slider ends show a big and a small "A"; no focus ring on the first quick-pick chip.
- Menu bar icon stays highlighted while the panel is open, without flicker: icon clicks are handled
  on mouse-down by an event monitor and not passed to the button's own click tracking.
- Clicking another app or menu bar item closes the panel; the menu bar stays visible in full-screen
  apps while the panel is open.

## 1.0.2 — 2026-11-15

- Larger menu bar icon (16 pt, medium weight) so it matches other items on the taller menu bar.

## 1.0.1 — 2026-11-15

- Security: the admin-privileged override write no longer copies from a temp file in a
  user-writable folder (which another process could swap for a symlink); the plist bytes
  are passed to the privileged command inline instead.

## 1.0.0 — 2026-11-15

First public release.

- Menu bar panel with a capsule slider over HiDPI "looks like" sizes and five quick-pick sizes.
- Sharpness readout in physical pixels per point.
- "Extended modes": adds a 16-point HiDPI ladder to the macOS display override plist.
- Built-in and external displays; sizes that don't fill a notched panel are filtered out.
- Panel opens on mouse-down, closes on focus loss / Space change, hides during a resolution
  switch and re-anchors under the icon afterwards.
- Global shortcut ⌃⌥⌘D, launch at login, light/dark mode, universal binary.
