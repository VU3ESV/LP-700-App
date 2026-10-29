# Changelog

All notable changes to **LP-700-App** — a native macOS client for the LP-700/LP-500
wattmeter that also ships as an [Amateur Radio Suite](https://github.com/VU3ESV/AmateurRadioSuite)
plugin. Format follows [Keep a Changelog](https://keepachangelog.com/); releases are
auto-cut on merge to `main` (tags `vX.Y.Z`).

## [Unreleased]

### Fixed
- **The Connect sheet no longer closes when you click the username or password field.** The
  URL field used `onCommit`, which on macOS also fires when the field loses focus, so moving to
  the Proxy login connected and closed the sheet. Return still connects (the Connect button is
  the default action).
- **Proxy login: a pasted password no longer keeps its trailing line break.** Save now drops
  leading/trailing newlines and refuses other control characters. Before, a copy from a terminal
  stored a wrong password in the shared `ShackProxy` Keychain item and every app got
  "Proxy login rejected".


### Added
- **Proxy login** for a server behind an authenticating TLS reverse proxy (Caddy, HTTP
  Basic auth): connect to `https://<host>:8089` and save the login under **Proxy login** in
  the Connect sheet (login Keychain, generic password, service `ShackProxy`, account = the
  username). `Authorization: Basic …` goes on the WebSocket upgrade and every request to
  the server, only over https/wss, never over plain http/ws. A 401 reads *Proxy login
  required* (none sent) or *Proxy login rejected* (wrong login), in the meter pane, the
  sheet and Preferences, and the retry waits at least 30 s. No `Origin` header, no
  certificate pinning: the proxy's CA must be trusted by macOS.
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
- **The plugin reports the app's release version.** The `.appex`'s `CFBundleShortVersionString` /
  `CFBundleVersion` and `plugin.json`'s `version` were fixed at 1.0 / 1.0.0 while the app shipped
  as 0.1.x. Both are now stamped with the release `VERSION` by `scripts/make-radioplugin.sh` and
  `scripts/package-signed.sh`, so the Suite's plugin manager, `pluginkit` and System Settings show
  the same version as the app. Suite catalog note: the LP-700 entry's `latestVersion` (1.0.0) has
  to move to the app's scheme, or the Suite will keep reporting an update as available.
### Fixed
- **Range greys out in CH Auto again.** The Controls card's **Rng** button stayed clickable
  with the meter's channel on Auto, but the meter ignores Range (and Alarm) changes there:
  the LP-500 user guide says of both "This choice can't be changed when the CH button is in
  Auto", and a bench test on the LP-700 agrees. **Rng** now greys out alongside **Alm**,
  matching the keypad, and a grey note under the Controls card says to pick CH 1–4. This
  undoes the 0.1.2 change that enabled Range in CH Auto on a misreading of the manual.
- **Hosted plugin connects on its own.** Loaded in the Amateur Radio Suite (the `.appex`),
  LP-700 now connects to the saved server as soon as it appears and opens the Connect sheet
  only when no server has been configured yet. Previously it sat disconnected until the
  operator opened the connection settings and pressed Connect on every launch. The standalone
  window, the in-process plugin and the hosted extension now share one
  `MeterViewModel.configuredServerURL` rule for "is a server configured". The hosted
  extension keeps its URL in its own sandboxed defaults, so the Suite asks once even when the
  standalone app is already set up. While hosted, the Connect sheet no longer offers **Quit**
  (it would have terminated the Suite or the extension process), and a connect attempt that is
  superseded while the saved server is unreachable no longer hijacks the newer connection.
- **Auto-reconnect actually reconnects.** `WSClient`'s disconnect handler cancelled the task it
  was running on before sleeping, so after a dropped connection, a server restart, or a launch
  before the server was up no retry ever happened: the app showed Offline until the operator
  reconnected by hand. Retries now run on their own task with the intended 0.5–10 s backoff,
  the badge says Reconnecting (not Offline) while a retry is pending, and Connected waits for
  the first frame instead of flashing on every attempt. `stop()` is final: a socket it cancelled,
  or one a reconnect replaced, can no longer schedule a retry of its own (or run the disconnect
  handler twice on the heartbeat path). Regression tests connect to a closed port and expect a
  second attempt, expect no retry after `stop()`, and expect no retry when `stop()` lands while
  a handshake is still pending.

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
