# focus

[![Tests](https://github.com/nchourrout/focus/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/nchourrout/focus/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue.svg)](#build--install)

A macOS menu bar app + CLI to get in the zone.

- **Block distracting websites** by editing `/etc/hosts`
- **Play focus music** via Spotify or a local audio file
- **Run a pomodoro** as a detached daemon that blocks sites, plays music, and cleans up automatically
- One Swift binary is both the menu bar app (run with no args) and the CLI (run with a subcommand)

> The repo was originally a Python script, archived at the tag [`v0-python`](https://github.com/nchourrout/focus/tree/v0-python). The Swift rewrite is wire-compatible: same `/etc/hosts` markers, same `~/.focus-pomodoro.json` schema.

## Build & install

Requires macOS 13+ and Swift 5.10+. Xcode Command Line Tools are enough to build; `swift test` needs a full Xcode.

```bash
git clone git@github.com:nchourrout/focus.git ~/dev/focus
cd ~/dev/focus
./Scripts/install.sh            # builds Focus.app, installs to /Applications,
                                # symlinks /usr/local/bin/focus → the inner binary
./Scripts/install-sudoers.sh    # writes /etc/sudoers.d/focus after visudo -c
open /Applications/Focus.app    # launches the menu bar app
```

To auto-launch on login, add `Focus.app` under System Settings → General → Login Items.

## Menu bar

Click the icon for a dropdown:

- **🍅 timer / ☕ break** icon with a live countdown while a pomodoro runs
- **Start pomodoro…** — prompts for a goal; replaced by **Stop pomodoro** while running
- **Block / Unblock websites** — toggles `/etc/hosts` (uses the sudoers drop-in)
- **Music** submenu — any preset, or Stop
- **Quit Focus**

Menu actions shell out to the same binary in CLI mode, so `~/.focus-pomodoro.json` stays the single source of truth. The menu bar polls it once a second.

## CLI

```bash
focus status                     # human-readable block status
focus status --json              # {"active": true|false}

sudo focus block                 # block sites from the bundled block.txt
sudo focus unblock               # remove the block
sudo focus toggle --json         # toggle; emits the new state

focus music --list               # built-in presets
focus music deepfocus            # play a preset
focus music spotify:playlist:X   # raw URI
focus music --file ~/brown.mp3 --loop
focus music --stop

focus pomodoro start "write spec"                 # 25min work, 5min break
focus pomodoro start "deep work" --work 50 --break 10 --music lofi
focus pomodoro status                             # add --json for machine-readable
focus pomodoro stop
```

## Sudoers

`block`, `unblock`, and `toggle` need root because they write `/etc/hosts`. The pomodoro daemon runs them non-interactively via `sudo -n`, so `NOPASSWD` is required:

```bash
./Scripts/install-sudoers.sh
```

Installs `/etc/sudoers.d/focus` with four whitelisted subcommands (no wildcard), validated with `visudo -cf` before writing.

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
