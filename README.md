# focus

<img src="docs/icon.png" alt="Focus icon" width="128" align="right" />

[![Tests](https://github.com/nchourrout/focus/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/nchourrout/focus/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue.svg)](#build--install)

A macOS menu bar app + CLI to get in the zone.

- **Block distracting websites** by editing `/etc/hosts`
- **Play focus music** from seven free, ad-free [SomaFM](https://somafm.com) stations (no account), any HTTP(S) stream URL, or a local file. Streams fade in and out rather than cutting, and duck under the phase cues
- **Run a pomodoro** as a detached daemon that blocks sites, plays music, and cleans up after itself. The block lifts during breaks and returns for the next work phase. It keeps cycling until you stop it, with a longer break every 4 sessions, or runs a single session
- **Keep a few tasks for today**, from the menu or the CLI, and start a pomodoro on one
- **See how much you focused**, per day, in Settings or with `focus stats`
- **Global hotkeys** and a **launch at login** toggle, both configured in Settings
- One Swift binary is both the menu bar app (no args) and the CLI (a subcommand)

<p align="center">
  <img src="docs/screenshots/menu-panel.png" alt="Menu bar panel during a work session, with today's tasks" width="250" />
  <img src="docs/screenshots/settings-stats.png" alt="Stats: focused time per day over the last 7 days" width="270" />
  <img src="docs/screenshots/settings-general.png" alt="General settings: session length, blocking, music and cycling" width="270" />
</p>

## Download

Pre-built `.app` zips are attached to each [GitHub Release](https://github.com/nchourrout/focus/releases). Unzip, drag `Focus.app` to `/Applications`, then:

```bash
xattr -dr com.apple.quarantine /Applications/Focus.app
open /Applications/Focus.app
```

The app is unsigned, so Gatekeeper blocks the first launch until that `xattr` runs (or right-click → Open). The zip doesn't create the CLI symlink — build from source if you want `focus` on `$PATH`.

## Build & install

Requires macOS 13+ and Swift 5.10+. Command Line Tools are enough to build. Views use `@ViewState` rather than `@State`: on the macOS 27 SDK `@State` is a macro whose plugin ships only with Xcode. Running the tests without Xcode takes a few extra flags, see [Testing](#testing).

```bash
git clone git@github.com:nchourrout/focus.git ~/dev/focus
cd ~/dev/focus
./Scripts/install.sh            # builds Focus.app, installs to /Applications,
                                # symlinks /usr/local/bin/focus → the inner binary
open /Applications/Focus.app
```

The first time you toggle the block, Focus pops a native admin password dialog, copies its binary to the root-owned `/Library/PrivilegedHelperTools/com.nchourrout.focus/`, and installs `/etc/sudoers.d/focus` pointing at that copy; after that everything runs silently. The rule never names the binary in `/Applications`, which the user can overwrite. `install.sh` refreshes the copy on upgrade; with a zip upgrade, Settings shows "needs update" until you click Update. `install.sh` strips the quarantine flag — if you ever see "Focus can't be opened because Apple cannot check it," run `sudo xattr -dr com.apple.quarantine /Applications/Focus.app`.

> KeyboardShortcuts is pinned to 1.15.0 so Command Line Tools stay sufficient. 1.16.0+ use the `#Preview` macro and 3.x also uses SwiftUI's `@Entry`; both need macro plugins that ship only with the full Xcode.

## Menu bar

- **stopwatch** during work, **coffee cup** during the break, with a live `mm:ss` countdown. Idle shows a dashed circle, or a slashed one when the block is on
- The goal can sit next to the countdown (**Settings → General → Show the goal in the menu bar**, off by default, capped at 20 characters so the bar stays narrow)
- Clicking the icon opens a panel with three parts:
  - **Session**: phase, live countdown, goal and progress, with Pause, Stop and Skip break. Idle, it offers **Start on "<first open task>"**, or **Other goal…** to type one
  - **Today**: up to 3 open tasks. Tick the circle to mark one done; hover for **Start** and **Remove**; type in the last row and press Return to add one. The running task is tagged NOW. Finished tasks drop off at midnight, open ones carry over
  - **Footer**: Block toggle, Music picker, time focused today, and the gear for **Settings…** (⌘,) and **Quit** (⌘Q)
- Settings has General, Blocking (permission, DNS-over-HTTPS, the site list), Shortcuts, and Stats (focused time per day over 7 or 30 days)

Session actions shell out to the same binary in CLI mode, so `~/.focus-pomodoro.json` stays the single source of truth; the menu bar watches it and refreshes as soon as it changes, with a 5s heartbeat to catch a daemon that died without cleaning up. Starting a pomodoro passes no flags — the CLI reads the same Settings the menu would, so the rules live in one place.

## CLI

```bash
focus status                     # block status; --json for {"active": true|false}
sudo focus block                 # block sites from block.txt
sudo focus unblock
sudo focus toggle --json

focus music --list               # built-in stations, least eventful first
focus music groovesalad          # a preset, or any http(s) stream URL
focus music --file ~/brown.mp3 --loop
focus music --stop

focus pomodoro start "write spec"                 # uses your Settings, cycles until stopped
focus pomodoro start "deep work" --work 50 --break 10 --music groovesalad
focus pomodoro start "quiet hour" --no-block
focus pomodoro status                             # add --json
focus pomodoro skip-break                         # end the current break early
focus pomodoro pause                              # freeze the session; block lifts, music stops
focus pomodoro resume                             # continue where it left off
focus pomodoro stop

focus stats                                       # today, last 7 days, one bar per day; --days N, --json

focus todo                                        # today's tasks; --json
focus todo add write the spec                     # at most 3 open
focus todo done 1                                 # undo 1 reopens it
focus todo rm 1
focus pomodoro start --todo 1                     # task 1 as the goal
```

Every pomodoro flag is an override: omit one and the session uses your Settings value (25/5 out of the box), so the CLI and the menu bar start identical sessions. Cycling and the long-break length and cadence live in **Settings → General**, and are re-read at each phase boundary — change one mid-run and it takes effect at the next transition, not the next run.

The station list runs least eventful first. What makes a stream good for focus is mostly what it doesn't do, so `dronezone`, `darkzone`, `deepspaceone` and `synphaera` lead: ambient, no vocals, nothing that resolves. `groovesalad`, `cliqhop` and `missioncontrol` have beats, and `missioncontrol` mixes in NASA mission audio, which is intermittent speech and the worst thing to have running behind any work involving language. They are kept because some people want them, not because they are the best default.

### Adding a station

Adding a station is not just a URL. AVPlayer will happily connect to a stream it cannot decode, pull it at full bitrate and render silence, with no error and a live subprocess, so "the process stayed up" proves nothing. Radio Paradise (raw ADTS AAC) and Ambient Sleeping Pill (HTTP/1.0 Icecast) both fail that way, which is why every station here is SomaFM despite that being a single point of failure. Check that macOS actually registers audio output:

```bash
focus music --uri <url> && sleep 12
pmset -g assertions | grep "$(head -1 ~/.focus-music.pid)"   # a line here means real audio
ps -p "$(head -1 ~/.focus-music.pid)" -o time=                # and CPU should climb ~0.15s/10s
```

Music sources are HTTP(S) streams (via `AVPlayer`) or local files (via `afplay`), both in detached subprocesses. A pomodoro picks its music in this order: `--music`, then the **Start music with pomodoro** preset, then `FOCUS_MUSIC_URI` (which also applies when the preset is **None**). A `--music` value naming no preset is an error; an unusable `FOCUS_MUSIC_URI` just means the session starts without music.

### Audio transitions

Nothing about the music starts or stops abruptly, because a hard edge in the audio is an attention event, which is the one thing focus music must not be.

- **Fades.** A stream fades in over 2s on every connect, reconnects included, and fades out over 1.2s when asked to stop, so switching stations ends the old one gently rather than clipping it. The ramps are linear in decibels rather than in amplitude, so the change is heard at an even rate instead of racing through the audible tail in the last few percent ([`VolumeFade`](Sources/Focus/Core/AudioFade.swift)).
- **Ducking.** Phase cues used to arrive at the same level as the music and get lost in it. The music now drops 12 dB for the length of the cue and comes back up slowly afterwards. The menu bar app signals the stream subprocess directly (SIGUSR1/SIGUSR2) since it only holds its PID. Local files played through `afplay` have no volume control, so the station label is checked first, and the recorded start time is checked too: SIGUSR1 terminates by default, so a recycled PID must never be signalled.
- **Handoff.** `skip-break` replaces the running daemon with one that continues the same run, and used to tear playback down with it: a fade-out, a reconnect and a fade-in to land back on the same station. The outgoing daemon now gets SIGUSR1 instead of SIGTERM, which is the same cleanup minus the music, and the replacement adopts the stream already playing. `pause` still stops the music, since the session is genuinely frozen.

All ramp timings and levels live in [`AudioFade`](Sources/Focus/Core/AudioFade.swift), which both processes read so the cue never starts before the music has finished moving out of its way.

## Sudoers (system permission)

`block`, `unblock`, and `toggle` write `/etc/hosts`, and the daemon runs them via `sudo -n`, so a `NOPASSWD` entry in `/etc/sudoers.d/focus` is required. Focus installs it itself: the first Block toggle prompts with the native admin dialog and writes the rule after `visudo -cf` validation. Re-run it any time from **Settings → Blocking → Grant…**, for instance after upgrading from a zip, when Settings shows "needs update".

The rule never names the binary in `/Applications`, which any process running as you could overwrite. The installer copies the binary to the root-owned `/Library/PrivilegedHelperTools/com.nchourrout.focus/focus`, checks its hash as root, and whitelists `block`, `unblock`, and `toggle` against that copy only, with their documented flag combinations and no wildcards. See [`SudoersInstaller.renderRule`](Sources/Focus/Core/SudoersInstaller.swift).

## State files

- `/etc/hosts` — block entries between `# === FOCUS BLOCK START/END ===` markers
- `/etc/hosts.backup` — first-block backup
- `~/.focus-pomodoro.json` — active session (goal, pid, started_at, daemon_started_at, work_end, break_end, music, block, session_number, is_long_break, work_minutes, break_minutes, paused_at). `started_at` is when the current work phase began and moves at every cycle boundary; `daemon_started_at` is the daemon process's own start time and does not, which is what identifies the pid as still ours. A record with `paused_at` set sits frozen until resumed; starting a new session first requires resuming or stopping it.
- `~/.focus-music.pid` — playback PID, station label, and the process start time (`pid\nlabel\nstarted_at`). `--stop` reaches the process, the menu bar names what's playing, and the start time proves the PID has not been recycled before a duck request is sent to it
- `~/Library/Application Support/Focus/history.jsonl` — one JSON line per finished work phase (plus `completed: false` partials when a run is stopped mid-work); feeds `focus stats`, the Stats tab and the time shown in the menu bar panel
- `~/Library/Application Support/Focus/todos.json`: today's tasks (`id`, `title`, `created_at`, `done_at`), shared by `focus todo` and the menu. Written atomically under a lock, so a menu click and a terminal command can't lose each other's edit

## Logs

The daemon and the music subprocesses are detached with their stdio on `/dev/null`, so anything they print is lost. Diagnostics go to Unified Logging instead — Console.app filtered on the subsystem, or:

```bash
log stream --predicate 'subsystem == "com.nchourrout.focus"'
log show --last 30m --predicate 'subsystem == "com.nchourrout.focus"'
```

Categories: `daemon`, `playback`, `actions`, `launch-at-login`, `terminate`.

Worth knowing: a failing `sudo -n block` is the quietest thing Focus can do wrong — the session runs normally and the state file says `block: true`, but the sites stay reachable. It's logged under `daemon` with sudo's own stderr attached, which is the fastest way to tell a missing drop-in from a rule that doesn't list the binary path you're running.

## Testing

Tests under `Tests/FocusTests/` use Swift Testing (`#expect`, `@Test`), and CI runs them on every push. With a full Xcode, `swift test` just works. With Command Line Tools only, the Testing framework is not on the default search or runtime paths, so link it next to the test bundle once and pass the paths explicitly:

```bash
FWK=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift build --build-tests
ln -sfn "$FWK/Testing.framework" .build/debug/Testing.framework
ln -sfn /Library/Developer/CommandLineTools/Library/Developer/usr/lib/lib_TestingInterop.dylib .build/debug/lib_TestingInterop.dylib
swift test -Xswiftc -F -Xswiftc "$FWK" -Xlinker -F -Xlinker "$FWK" \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

The symlinks are needed because SIP strips `DYLD_FRAMEWORK_PATH` from the test runner, so the framework has to sit where the bundle's rpath already looks. `-plugin-path` is needed from the macOS 27 SDK on.

## Releasing

`VERSION` at the repo root is the single source of truth for `CFBundleShortVersionString`.

```bash
./Scripts/release.sh 0.6.0      # bumps VERSION, commits, tags v0.6.0
git push && git push origin v0.6.0
```

The tag push triggers `release.yml`, which builds `Focus.app` on a clean macos-15 runner and attaches the zip to a new GitHub Release.

## License

MIT — see [LICENSE](LICENSE).
