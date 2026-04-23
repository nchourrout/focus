# focus

A tiny macOS CLI to get in the zone. Three things:

1. **Block distracting websites** by editing `/etc/hosts`.
2. **Play focus music or sounds** via Spotify or a local audio file.
3. **Pair with a Pomodoro timer** (driven from Hammerspoon) so blocking and music start/stop with the session.

Python 3, no dependencies, single file.

## Install

```bash
git clone git@github.com:nchourrout/focus.git ~/dev/focus
```

`block` and `unblock` need sudo (they write `/etc/hosts`). To make them work from Hammerspoon without a password prompt, add a sudoers drop-in:

```bash
sudo tee /etc/sudoers.d/focus >/dev/null <<EOF
$(whoami) ALL=(root) NOPASSWD: /usr/bin/python3 $HOME/dev/focus/focus.py block *, /usr/bin/python3 $HOME/dev/focus/focus.py unblock *
EOF
sudo chmod 0440 /etc/sudoers.d/focus
```

## Usage

```bash
# Website blocking
sudo ./focus.py block              # block sites in block.txt
sudo ./focus.py unblock            # remove the block
./focus.py status                  # human-readable
./focus.py status --json           # {"active": true|false}

# Music / sounds
./focus.py music                   # play $FOCUS_SPOTIFY_URI on Spotify
./focus.py music --uri spotify:playlist:XXXX
./focus.py music --file ~/Music/brown-noise.mp3 --loop
./focus.py music --stop            # pause Spotify and kill any local playback
```

Set a default Spotify playlist in your shell:

```bash
export FOCUS_SPOTIFY_URI="spotify:playlist:37i9dQZF1DX0XUsuxWHRQd"
```

## Hammerspoon integration

```lua
local FOCUS = os.getenv("HOME") .. "/dev/focus/focus.py"

local function focus(args, cb)
  hs.task.new("/usr/bin/python3", function(ec) if cb then cb(ec == 0) end end, args):start()
end

-- Hyper+B toggles blocking (requires sudoers drop-in above)
hs.hotkey.bind(hyper, "b", function()
  focus({FOCUS, "status", "--json"}, function(ok, out)
    local active = out and out:find('"active": true') ~= nil
    local cmd = active and "unblock" or "block"
    hs.task.new("/usr/bin/sudo", nil, {"/usr/bin/python3", FOCUS, cmd}):start()
  end)
end)
```

## Config

- `block.txt` (next to `focus.py`): one site per line. `www.` is added automatically, so list the bare domain.
- `FOCUS_SPOTIFY_URI` (env): default Spotify URI for `focus music`.

## Notes

- Keeps a backup of `/etc/hosts` at `/etc/hosts.backup` the first time it writes.
- Flushes the DNS cache after each block/unblock.
- Local file playback is tracked via `~/.focus-music.pid` so `--stop` can kill it.
