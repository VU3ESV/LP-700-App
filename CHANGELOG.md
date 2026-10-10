# Changelog

All notable changes to **LP-700-App** — a native macOS client for the LP-700/LP-500
wattmeter that also ships as an [Amateur Radio Suite](https://github.com/VU3ESV/AmateurRadioSuite)
plugin. Format follows [Keep a Changelog](https://keepachangelog.com/); releases are
auto-cut on merge to `main` (tags `vX.Y.Z`).

## [Unreleased]

### Added
- **Update check** against this repo's GitHub releases: about 10 s after launch, then at
  most once a day (one anonymous `api.github.com` request), the standalone app says when a
  newer release is out — Download (opens the release page) / Skip This Version / Remind Me
  Later. **LP-700 ▸ Check for Updates…** checks on demand; **Preferences → Updates** turns
  the automatic check off. Never downloads or installs anything; silent when offline;
  development builds (`0.0.0-dev`) never check on their own. The suite plugin never checks.
  The dialog an automatic check puts up never takes the keyboard or brings the app forward,
  and none of its buttons is the default — Return can't open the browser while you type;
  Download needs a click, Esc is Remind Me Later.
- **Plugin build & release pipeline** ([CONVERTING-A-PLUGIN.md §7](https://github.com/VU3ESV/AmateurRadioSuite/blob/main/docs/CONVERTING-A-PLUGIN.md)):
  CI now builds the `.appex`/`.radioplugin` on every PR (catching extension breakage early),
  and each release attaches `LP-700-App-<version>.radioplugin` (with its `.sha256`) alongside
  the `.dmg`.

### Changed
- **Leaner local builds.** `scripts/install-local.sh` now builds only this Mac's architecture
  and strips local symbols (`ARCHS=native STRIP=1`), halving compile time and cutting the
  installed binary to about a fifth of the universal release's, for an install that never runs
  on another Mac. Both knobs are new options of `scripts/build-app.sh`; its defaults
  (universal, symbols kept) and therefore the released DMGs are unchanged.

## [0.1.5] — 2026-06-02
### Added
- **Out-of-process plugin** ([#9](https://github.com/VU3ESV/LP-700-App/pull/9)): an
  ExtensionKit `.appex` target + `scripts/make-radioplugin.sh` that packages
  `LP700.radioplugin`, so the suite can browse/install LP-700 and host it sandboxed via
  `EXHostViewController`. Adds a public `LP700Extension.rootView()` factory; the standalone
  app and in-process plugin are unchanged.

## [0.1.4] — 2026-06-02
### Changed
- **Release on merge** ([#8](https://github.com/VU3ESV/LP-700-App/pull/8)): pushing to
  `main` (i.e. a merged PR) auto-bumps the latest `vX.Y.Z` tag and cuts a GitHub Release.
- **RadioPluginKit 1.2 manifest** ([#7](https://github.com/VU3ESV/LP-700-App/pull/7)):
  adopted the typed manifest/capabilities, synced with the suite contract.

## [0.1.3] — 2026-05-31
### Added
- **Plugin architecture** ([#6](https://github.com/VU3ESV/LP-700-App/pull/6)): a `public
  LP700Plugin` adapter conforming to `RadioPlugin` lets the Amateur Radio Suite host LP-700
  in-process; all views/view-models/networking stay `internal`. Per-plugin `UserDefaults`
  via `host.defaults(for:)`.

## [0.1.2] — 2026-05-23
### Added
- Power/SWR card: enable **Range** in CH-Auto and always auto-scale the bargraph
  ([#5](https://github.com/VU3ESV/LP-700-App/pull/5)).
- Hardware-style combined **Power & SWR** card with graduated 18-pt bargraphs and derived
  Pr ([#4](https://github.com/VU3ESV/LP-700-App/pull/4)).
### Fixed
- WebSocket: removed a leading-edge telemetry throttle that stalled the UI on idle
  ([#3](https://github.com/VU3ESV/LP-700-App/pull/3)).
- Re-open the main window from the menu-bar popover after it was closed.
### Performance
- Cut idle CPU ~30 % → ~11 % via a value-typed view subtree and a 5 Hz refresh cap.

## [0.1.1] — 2026-05-09
### Added
- Color power-scale bars on the Avg/Peak cards ([#1](https://github.com/VU3ESV/LP-700-App/pull/1)).
- Gate Range/Alarm in the UI when auto-channel locks them; QRP-friendly bar scale
  ([#2](https://github.com/VU3ESV/LP-700-App/pull/2)).
- Peak Power respects `peak_mode` and surfaces `peak_hold_w`.

## [0.1.0] — 2026-05-08
### Added
- Initial native macOS SwiftUI client for the LP-700 WebSocket server: live telemetry,
  connection sheet, setup/preferences, menu-bar item, user manual + screenshots, and a
  universal `.app` / `.dmg` release pipeline.
