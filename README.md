# focus

[![Tests](https://github.com/nchourrout/focus/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/nchourrout/focus/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue.svg)](#build--install)

A macOS menu bar app + CLI to get in the zone.

- **Block distracting websites** by editing `/etc/hosts`
- **Play focus music** from free, ad-free [SomaFM](https://somafm.com) streams (Drone Zone, Groove Salad, Mission Control, …) — or a Spotify URI / local audio file
- **Run a pomodoro** as a detached daemon that blocks sites, plays music, and cleans up automatically
- **Global hotkeys** for start/stop pomodoro and toggle block, configurable in Settings
- **Launch at login** toggle via `SMAppService`
- One Swift binary is both the menu bar app (run with no args) and the CLI (run with a subcommand)

> The repo was originally a Python script, archived at the tag [`v0-python`](https://github.com/nchourrout/focus/tree/v0-python). The Swift rewrite is wire-compatible: same `/etc/hosts` markers, same `~/.focus-pomodoro.json` schema.

## Build & install

Requires macOS 13+ and Swift 5.10+. Xcode Command Line Tools are enough to build; `swift test` needs a full Xcode.

```bash
git clone git@github.com:nchourrout/focus.git ~/dev/focus
cd ~/dev/focus
./Scripts/install.sh            # builds Focus.app, installs to /Applications,
                                # symlinks /usr/local/bin/focus → the inner binary
open /Applications/Focus.app    # launches the menu bar app
```

The first time you toggle the block, Focus pops a native admin password dialog and installs `/etc/sudoers.d/focus`. After that, all toggles and pomodoro auto-blocks run silently. You can also manage the permission from **Settings → General → Grant permission…** at any time.

Open **Settings…** from the menu (⌘,) to bind global hotkeys and toggle launch-at-login.

The `.app` is unsigned; `install.sh` strips the quarantine flag so Gatekeeper doesn't block first-open. If you ever see "Focus can't be opened because Apple cannot check it," run `sudo xattr -dr com.apple.quarantine /Applications/Focus.app`.

## Menu bar

Click the icon for a dropdown:

- **🍅 timer / ☕ break** icon with a live countdown while a pomodoro runs
- **Start pomodoro…** — prompts for a goal; replaced by **Stop pomodoro** while running
- **Block / Unblock websites** — toggles `/etc/hosts` (uses the sudoers drop-in)
- **Music** submenu — any preset, or Stop
- **Settings…** — tabbed window with General (launch at login) and Shortcuts (global hotkey recorders)
- **Quit Focus**

Menu actions shell out to the same binary in CLI mode, so `~/.focus-pomodoro.json` stays the single source of truth. The menu bar polls it once a second.

## CLI

```bash
focus status                     # human-readable block status
focus status --json              # {"active": true|false}

sudo focus block                 # block sites from the bundled block.txt
sudo focus unblock               # remove the block
sudo focus toggle --json         # toggle; emits the new state

focus music --list               # built-in SomaFM streams
focus music groovesalad          # stream a preset (no Spotify needed)
focus music https://stream.url   # any HTTP(S) audio stream
focus music spotify:track:X      # Spotify track (plays immediately)
focus music spotify:playlist:X   # Spotify playlist (navigates; press Play)
focus music --file ~/brown.mp3 --loop
focus music --stop

focus pomodoro start "write spec"                 # 25min work, 5min break
focus pomodoro start "deep work" --work 50 --break 10 --music lofi
focus pomodoro status                             # add --json for machine-readable
focus pomodoro stop
```

**Music sources**:
- **HTTP(S) streams** (built-in SomaFM presets, or any direct stream URL) play immediately via AVPlayer in a detached subprocess.
- **Spotify track URIs** auto-play via AppleScript.
- **Spotify playlist/album URIs** can't auto-play — Spotify's AppleScript only switches playback context for tracks, and we don't ship Web API OAuth. Focus navigates Spotify to the playlist; press Play (or spacebar) to start.
- **Local audio files** play via `afplay`, with optional `--loop`.

## Sudoers (system permission)

`block`, `unblock`, and `toggle` need root because they write `/etc/hosts`. The pomodoro daemon runs them non-interactively via `sudo -n`, so a `NOPASSWD` entry is required in `/etc/sudoers.d/focus`.

Focus installs it itself — no separate shell script:

- On the first Hyper+B / Block toggle, the app detects the missing drop-in and prompts with the **native macOS admin password dialog** (same UX as Xcode, Homebrew-cask, etc.). Enter your password once; the rule is written after `visudo -cf` validation.
- You can re-run the install from **Settings → General → Grant permission…** at any time (e.g. if the binary path changes).

The generated rule whitelists exactly four subcommands (`block`, `unblock`, `toggle`, `toggle --json`) against the Focus.app binary path — no wildcards.

## State files

- `/etc/hosts` — block entries between `# === FOCUS BLOCK START/END ===` markers
- `/etc/hosts.backup` — first-block backup
- `~/.focus-pomodoro.json` — active session (goal, pid, work_end, break_end, music)
- `~/.focus-music.pid` — afplay PID for `--stop`

## Testing

Unit tests under `Tests/FocusTests/` use Swift Testing (`#expect`, `@Test`). CI runs them on every push via GitHub Actions — see the badge at the top.

Locally with a full Xcode install:

```bash
swift test
```

Without Xcode, `swift build` still works; only `swift test` needs the full toolchain.

## License

MIT — see [LICENSE](LICENSE).
