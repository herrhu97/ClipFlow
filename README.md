# ClipFlow

ClipFlow is a local-first macOS clipboard history manager. It runs in the menu bar, records text, rich text, links, images, and files, and opens a keyboard-driven quick panel with `Command-Shift-V`.

## MVP features

- SQLite-backed history with transactional writes and corruption recovery
- AES-256-GCM encryption for clipboard text, search data, and external payloads
- Encryption key stored in the macOS Keychain
- Pasteboard privacy markers, password-manager exclusions, and sensitive-pattern filtering
- Search by content, file name, source application, and group
- Type, time, favorites, and group filters
- Pinning, user-created groups, retention limits, and storage-size cleanup
- Accessibility-aware automatic paste with a manual `Command-V` fallback
- Menu-bar pause control, configurable global shortcut, onboarding, export, and full deletion
- Light/dark appearance, multiple-screen positioning, and encrypted image payloads loaded on demand

## Build and run

The project requires macOS 13 or newer and the Apple Swift toolchain.

```sh
./scripts/build-app.sh
open dist/ClipFlow.app
```

The generated app is ad-hoc signed for local development. Move it to `/Applications` before enabling launch at login. A distribution build should use a Developer ID signature and notarization.

You can also run the unbundled debug executable with `swift run`, though Accessibility and launch-at-login behavior should be tested from the `.app` bundle.

## Tests

```sh
./scripts/test.sh
```

The wrapper supplies the Swift Testing framework path used by Command Line Tools-only installations. It falls back to the standard `swift test` command when a full Xcode toolchain is active.

## Local data

History is stored under `~/Library/Application Support/ClipFlow`. Clearing history removes database rows, encrypted payload files, and SQLite WAL data before compacting the database. ClipFlow does not include analytics or cloud sync in this MVP.
