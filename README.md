# focus

<img src="docs/icon.png" alt="Focus icon" width="128" align="right" />

[![Tests](https://github.com/nchourrout/focus/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/nchourrout/focus/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue.svg)](#build--install)

A macOS menu bar app + CLI to get in the zone.

- **Block distracting websites** by editing `/etc/hosts`
- **Play focus music** from free, ad-free [SomaFM](https://somafm.com) streams, any HTTP(S) stream URL, or a local file
- **Run a pomodoro** as a detached daemon that blocks sites, plays music, and cleans up after itself. The block lifts during breaks and returns for the next work phase. It keeps cycling until you stop it, with a longer break every 4 sessions — or stops after each set and asks whether to start another
- **Global hotkeys** and a **launch at login** toggle, both configured in Settings
- One Swift binary is both the menu bar app (no args) and the CLI (a subcommand)

## Download

Pre-built `.app` zips are attached to each [GitHub Release](https://github.com/nchourrout/focus/releases). Unzip, drag `Focus.app` to `/Applications`, then:

```bash
xattr -dr com.apple.quarantine /Applications/Focus.app
open /Applications/Focus.app
```

The app is unsigned, so Gatekeeper blocks the first launch until that `xattr` runs (or right-click → Open). The zip doesn't create the CLI symlink — build from source if you want `focus` on `$PATH`.

## Build & install

Requires macOS 13+ and Swift 5.10+. Command Line Tools are enough to build; `swift test` needs a full Xcode.

```bash
git clone git@github.com:nchourrout/focus.git ~/dev/focus
cd ~/dev/focus
./Scripts/install.sh            # builds Focus.app, installs to /Applications,
                                # symlinks /usr/local/bin/focus → the inner binary
open /Applications/Focus.app
```

The first time you toggle the block, Focus pops a native admin password dialog and installs `/etc/sudoers.d/focus`; after that everything runs silently. `install.sh` strips the quarantine flag — if you ever see "Focus can't be opened because Apple cannot check it," run `sudo xattr -dr com.apple.quarantine /Applications/Focus.app`.

> KeyboardShortcuts is pinned to 1.15.0 so Command Line Tools stay sufficient. 1.16.0+ use the `#Preview` macro and 3.x also uses SwiftUI's `@Entry`; both need macro plugins that ship only with the full Xcode.

## Menu bar

- **stopwatch** during work, **coffee cup** during the break, with a live `mm:ss` countdown. Idle shows a dashed circle, or a slashed one when the block is on
- **Start pomodoro…** — prompts for a goal; becomes **Stop pomodoro** while running
- **Block / Unblock websites**
- **Music** — any preset, or Stop. The current station is named in the title and check-marked in the list
- **Settings…** (⌘,) — General, Shortcuts, and an inline editor for the Block list
- **Quit Focus**

Menu actions shell out to the same binary in CLI mode, so `~/.focus-pomodoro.json` stays the single source of truth; the menu bar polls it once a second. Starting a pomodoro passes no flags — the CLI reads the same Settings the menu would, so the rules live in one place.

## CLI

```bash
focus status                     # block status; --json for {"active": true|false}
sudo focus block                 # block sites from block.txt
sudo focus unblock
sudo focus toggle --json

focus music --list               # built-in SomaFM streams
focus music groovesalad          # a preset, or any http(s) stream URL
focus music --file ~/brown.mp3 --loop
focus music --stop

focus pomodoro start "write spec"                 # uses your Settings, cycles until stopped
focus pomodoro start "deep work" --work 50 --break 10 --music groovesalad
focus pomodoro start "quiet hour" --no-block
focus pomodoro status                             # add --json
focus pomodoro skip-break                         # end the current break early
focus pomodoro stop
```

Every pomodoro flag is an override: omit one and the session uses your Settings value (25/5 out of the box), so the CLI and the menu bar start identical sessions. Cycling, long-break length and cadence, and stop-after-set live in **Settings → General**, and are re-read at each phase boundary — change one mid-run and it takes effect at the next transition, not the next run.

Music sources are HTTP(S) streams (via `AVPlayer`) or local files (via `afplay`), both in detached subprocesses. A pomodoro picks its music in this order: `--music`, then the **Start music with pomodoro** preset, then `FOCUS_MUSIC_URI` (which also applies when the preset is **None**). A `--music` value naming no preset is an error; an unusable `FOCUS_MUSIC_URI` just means the session starts without music.

## Sudoers (system permission)

`block`, `unblock`, and `toggle` write `/etc/hosts`, and the daemon runs them via `sudo -n`, so a `NOPASSWD` entry in `/etc/sudoers.d/focus` is required. Focus installs it itself: the first Block toggle prompts with the native admin dialog and writes the rule after `visudo -cf` validation. Re-run it any time from **Settings → General → Grant permission…**, for instance if the binary path changes.

The rule whitelists `block`, `unblock`, and `toggle` against the Focus.app binary path with their documented flag combinations, no wildcards. See [`SudoersInstaller.renderRule`](Sources/Focus/Core/SudoersInstaller.swift).

## State files

- `/etc/hosts` — block entries between `# === FOCUS BLOCK START/END ===` markers
- `/etc/hosts.backup` — first-block backup
- `~/.focus-pomodoro.json` — active session (goal, pid, started_at, work_end, break_end, music, block, session_number, is_long_break, set_complete, work_minutes, break_minutes)
- `~/.focus-music.pid` — playback PID and station label (`pid\nlabel`), so `--stop` can reach it and the menu bar can name what's playing

## Logs

The daemon and the music subprocesses are detached with their stdio on `/dev/null`, so anything they print is lost. Diagnostics go to Unified Logging instead — Console.app filtered on the subsystem, or:

```bash
log stream --predicate 'subsystem == "com.nchourrout.focus"'
log show --last 30m --predicate 'subsystem == "com.nchourrout.focus"'
```

Categories: `daemon`, `playback`, `actions`, `launch-at-login`, `terminate`.

Worth knowing: a failing `sudo -n block` is the quietest thing Focus can do wrong — the session runs normally and the state file says `block: true`, but the sites stay reachable. It's logged under `daemon` with sudo's own stderr attached, which is the fastest way to tell a missing drop-in from a rule that doesn't list the binary path you're running.

## Testing

Tests under `Tests/FocusTests/` use Swift Testing (`#expect`, `@Test`), and CI runs them on every push. Locally, `swift test` needs a full Xcode; `swift build` works without one.

## Releasing

`VERSION` at the repo root is the single source of truth for `CFBundleShortVersionString`.

```bash
./Scripts/release.sh 0.6.0      # bumps VERSION, commits, tags v0.6.0
git push && git push origin v0.6.0
```

The tag push triggers `release.yml`, which builds `Focus.app` on a clean macos-15 runner and attaches the zip to a new GitHub Release.

## License

MIT — see [LICENSE](LICENSE).
