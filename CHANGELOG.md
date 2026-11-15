# Changelog

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
