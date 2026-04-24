# focus

A macOS CLI — soon menu bar app — to get in the zone.

- **Block distracting websites** by editing `/etc/hosts`
- **Play focus music** via Spotify or a local audio file
- **Run a pomodoro** as a detached daemon that blocks sites, plays music, and cleans up automatically
- Single Swift binary, no runtime dependencies
- State is wire-compatible with the previous Python version (same `/etc/hosts` markers, same `~/.focus-pomodoro.json` schema)

> The repo was originally a Python script. The Python code is archived at the
> git tag [`v0-python`](https://github.com/nchourrout/focus/tree/v0-python).

## Status

**Phase 1 — CLI parity (current).** The Swift binary matches the Python tool's
CLI surface 1:1. Menu bar app, global hotkeys, and settings come in later phases.

## Build & install

Requires macOS 13+ and Swift 5.10+ (Xcode Command Line Tools are enough to build;
Xcode itself is only needed to run `swift test`).

```bash
git clone git@github.com:nchourrout/focus.git ~/dev/focus
cd ~/dev/focus
./Scripts/install.sh            # builds release, symlinks /usr/local/bin/focus
./Scripts/install-sudoers.sh    # writes /etc/sudoers.d/focus after visudo -c
```

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
focus pomodoro status                             # or --json
focus pomodoro stop
```

## Sudoers

`block`, `unblock`, and `toggle` need root (they write `/etc/hosts`). The pomodoro
daemon also needs to run them in the background, so `NOPASSWD` is required:

```bash
./Scripts/install-sudoers.sh
```

Installs `/etc/sudoers.d/focus` with four whitelisted commands (no wildcard),
validated with `visudo -cf` before writing.

## State files

- `/etc/hosts` — block entries between `# === FOCUS BLOCK START/END ===` markers
- `/etc/hosts.backup` — first-block backup
- `~/.focus-pomodoro.json` — active session state (goal, pid, work_end, break_end, music)
- `~/.focus-music.pid` — afplay PID for `--stop`

## Testing

Unit tests under `Tests/FocusTests/` use Swift Testing. Run with `swift test`
when you have a full Xcode install. Without Xcode, `swift build` still works.

## License

MIT — see [LICENSE](LICENSE).
