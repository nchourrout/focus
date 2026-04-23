# focus

A tiny macOS CLI to get in the zone. Three things:

1. **Block distracting websites** by editing `/etc/hosts`.
2. **Play focus music or sounds** via Spotify or a local audio file.
3. **Run a Pomodoro timer** as a detached daemon that blocks sites and plays music for you, cleaning up when the session ends.

Python 3, no dependencies, single file.

## Install

```bash
git clone git@github.com:nchourrout/focus.git ~/dev/focus
```

`block`, `unblock`, and `toggle` need sudo (they write `/etc/hosts`). The pomodoro daemon also needs to block/unblock in the background, so a `NOPASSWD` sudoers drop-in is required for it to work from Hammerspoon:

```bash
FOCUS=$HOME/dev/focus/focus.py
sudo tee /etc/sudoers.d/focus >/dev/null <<EOF
$(whoami) ALL=(root) NOPASSWD: /usr/bin/python3 $FOCUS block, /usr/bin/python3 $FOCUS unblock, /usr/bin/python3 $FOCUS toggle, /usr/bin/python3 $FOCUS toggle --json
EOF
sudo chmod 0440 /etc/sudoers.d/focus
```

This whitelists the exact subcommands needed (no wildcard). Without it, background `sudo -n` calls fail silently and the pomodoro runs without blocking.

## Usage

```bash
# Website blocking
sudo ./focus.py block              # block sites in block.txt
sudo ./focus.py unblock            # remove the block
sudo ./focus.py toggle             # toggle block on/off (used by Hammerspoon)
./focus.py status                  # human-readable
./focus.py status --json           # {"active": true|false}

# Music / sounds
./focus.py music --list            # show built-in presets
./focus.py music deepfocus         # play a preset
./focus.py music spotify:playlist:XXXX   # play a raw URI
./focus.py music --file ~/Music/brown-noise.mp3 --loop
./focus.py music --stop            # pause Spotify and kill any local playback
./focus.py music                   # play $FOCUS_SPOTIFY_URI if set
```

Built-in presets: `deepfocus`, `piano`, `lofi`, `intense`, `ambient`. Edit `MUSIC_PRESETS` in `focus.py` to add your own.

Set a default Spotify playlist in your shell:

```bash
export FOCUS_SPOTIFY_URI="spotify:playlist:37i9dQZF1DX0XUsuxWHRQd"
```

```bash
# Pomodoro
./focus.py pomodoro start "write auth spec"          # 25 + 5 min, no music
./focus.py pomodoro start "refactor" --music lofi    # with a preset
./focus.py pomodoro start "deep work" --work 50 --break 10
./focus.py pomodoro status                           # "work — 23:12 left — ..."
./focus.py pomodoro status --json                    # for scripting
./focus.py pomodoro stop                             # cancel, unblock, stop music
```

`pomodoro start` forks a detached daemon that blocks sites, starts music, waits through work + break, then cleans up. State lives at `~/.focus-pomodoro.json` while active.

## Hammerspoon integration

A full integration (hotkey + menubar, reading the pomodoro state file Python writes) lives in my [mac-config](https://github.com/nchourrout/mac-config) repo under `hammerspoon/init.lua`. Shape:

```lua
local FOCUS = os.getenv("HOME") .. "/dev/focus/focus.py"
local POMODORO_STATE = os.getenv("HOME") .. "/.focus-pomodoro.json"

-- Hyper+B: toggle block
hs.hotkey.bind(hyper, "b", function()
  hs.task.new("/usr/bin/sudo", nil, {"/usr/bin/python3", FOCUS, "toggle"}):start()
end)

-- Hyper+O: start a pomodoro (menubar reads POMODORO_STATE each tick)
hs.hotkey.bind(hyper, "o", function()
  hs.task.new("/usr/bin/python3", nil,
    {FOCUS, "pomodoro", "start", "focus session", "--music", "lofi"}):start()
end)
```

## Config

- `block.txt` (next to `focus.py`): one site per line. `www.` is added automatically, so list the bare domain.
- `FOCUS_SPOTIFY_URI` (env): default Spotify URI for `focus music`.

## Notes

- Keeps a backup of `/etc/hosts` at `/etc/hosts.backup` the first time it writes.
- Flushes the DNS cache after each block/unblock.
- Local file playback is tracked via `~/.focus-music.pid` so `--stop` can kill it.
- Pomodoro runs as a detached process; state lives at `~/.focus-pomodoro.json`. `pomodoro stop` SIGTERMs the daemon, which unblocks and stops music in its `finally` block.
