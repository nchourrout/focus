#!/usr/bin/env python3
"""focus: block distracting websites and play focus music on macOS."""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

HOSTS_FILE = Path("/etc/hosts")
HOSTS_BACKUP = Path("/etc/hosts.backup")
MARKER_START = "# === FOCUS BLOCK START ==="
MARKER_END = "# === FOCUS BLOCK END ==="
REDIRECT_IP = "127.0.0.1"

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_BLOCK_FILE = SCRIPT_DIR / "block.txt"
MUSIC_PID_FILE = Path.home() / ".focus-music.pid"
POMODORO_STATE_FILE = Path.home() / ".focus-pomodoro.json"

# Curated focus playlists. Edit to taste. `focus music <name>` plays the URI.
MUSIC_PRESETS = {
    "deepfocus": "spotify:playlist:37i9dQZF1DX0XUsuxWHRQd",   # Deep Focus
    "piano":     "spotify:playlist:37i9dQZF1DX4sWSpwq3LiO",   # Peaceful Piano
    "lofi":      "spotify:playlist:37i9dQZF1DWWQRwui0ExPn",   # Lofi Beats
    "intense":   "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6",   # Intense Studying
    "ambient":   "spotify:playlist:37i9dQZF1DX3Ogo9pFvBkY",   # Ambient Relaxation
}

# Matches bare-ish hostnames. Rejects newlines, spaces, and shell-meta.
_HOSTNAME_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9.\-]*$")

_SELF = [sys.executable, str(SCRIPT_DIR / "focus.py")]


def _run_self(*args: str, sudo: bool = False) -> int:
    """Invoke this script again as a subprocess, silently."""
    cmd = (["sudo", "-n", *_SELF] if sudo else [*_SELF]) + list(args)
    return subprocess.run(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode


def _pid_alive(pid: int) -> bool:
    """True if `pid` exists and we can signal it (may be any living process)."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # Alive, just not ours.
    return True


def _escape_applescript(s: str) -> str:
    """Escape backslashes and double-quotes for embedding in an AppleScript string literal."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def positive_int(s: str) -> int:
    """argparse type: accept positive integers only."""
    v = int(s)
    if v <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return v


# --- website blocking ---------------------------------------------------------

def require_root() -> None:
    if os.geteuid() != 0:
        sys.exit("focus: this command needs sudo (it writes /etc/hosts)")


def read_block_list(path: Path) -> list[str]:
    sites: set[str] = set()
    for lineno, raw in enumerate(path.read_text().splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        # Strip leading www. so both variants are always emitted below.
        site = line.removeprefix("www.")
        # Reject anything that could smuggle newlines or extra tokens into /etc/hosts.
        if not _HOSTNAME_RE.match(site):
            sys.exit(f"focus: {path}:{lineno}: invalid hostname: {line!r}")
        sites.add(site)
    return sorted(sites)


def strip_block_section(content: str) -> str:
    out: list[str] = []
    skipping = False
    for line in content.splitlines():
        if MARKER_START in line:
            skipping = True
            continue
        if MARKER_END in line:
            skipping = False
            continue
        if not skipping:
            out.append(line)
    return "\n".join(out).rstrip() + "\n"


def flush_dns() -> None:
    # Already running as root; no sudo needed.
    subprocess.run(["dscacheutil", "-flushcache"], check=False)
    subprocess.run(["killall", "-HUP", "mDNSResponder"], check=False)


def backup_hosts_once() -> None:
    if not HOSTS_BACKUP.exists():
        HOSTS_BACKUP.write_text(HOSTS_FILE.read_text())


def is_active() -> bool:
    return MARKER_START in HOSTS_FILE.read_text()


def _apply_block(block_file: Path) -> int:
    sites = read_block_list(block_file)
    if not sites:
        sys.exit(f"focus: {block_file} is empty")
    backup_hosts_once()
    cleaned = strip_block_section(HOSTS_FILE.read_text())
    entries = [MARKER_START]
    for site in sites:
        entries.append(f"{REDIRECT_IP} {site}")
        entries.append(f"{REDIRECT_IP} www.{site}")
    entries.append(MARKER_END)
    HOSTS_FILE.write_text(cleaned + "\n".join(entries) + "\n")
    flush_dns()
    return len(sites)


def _apply_unblock() -> None:
    HOSTS_FILE.write_text(strip_block_section(HOSTS_FILE.read_text()))
    flush_dns()


def _resolve_block_file(path_str: str) -> Path:
    path = Path(path_str).expanduser()
    if not path.exists():
        sys.exit(f"focus: block file not found: {path}")
    return path


def cmd_block(args: argparse.Namespace) -> int:
    require_root()
    count = _apply_block(_resolve_block_file(args.file))
    print(f"focus: blocked {count} sites")
    return 0


def cmd_unblock(args: argparse.Namespace) -> int:
    require_root()
    _apply_unblock()
    print("focus: unblocked")
    return 0


def cmd_toggle(args: argparse.Namespace) -> int:
    require_root()
    if is_active():
        _apply_unblock()
        new_active = False
    else:
        _apply_block(_resolve_block_file(args.file))
        new_active = True
    if args.json:
        print(json.dumps({"active": new_active}))
    else:
        print("focus: " + ("blocked" if new_active else "unblocked"))
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    active = is_active()
    if args.json:
        print(json.dumps({"active": active}))
    else:
        print("focus: blocking is " + ("ACTIVE" if active else "INACTIVE"))
    return 0


# --- music --------------------------------------------------------------------

def osascript(script: str) -> int:
    return subprocess.run(
        ["osascript", "-e", script],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode


def spotify_play(uri: str) -> None:
    # Open Spotify if needed, then play the URI.
    osascript('tell application "Spotify" to activate')
    safe_uri = _escape_applescript(uri)
    rc = osascript(f'tell application "Spotify" to play track "{safe_uri}"')
    if rc != 0:
        sys.exit(f"focus: Spotify failed to play {uri}")


def spotify_pause() -> None:
    osascript('tell application "Spotify" to pause')


def kill_local_playback() -> None:
    if not MUSIC_PID_FILE.exists():
        return
    try:
        pid = int(MUSIC_PID_FILE.read_text().strip())
        os.killpg(pid, signal.SIGTERM)
    except (ValueError, ProcessLookupError, PermissionError):
        pass
    MUSIC_PID_FILE.unlink(missing_ok=True)


def start_local_playback(path: Path, loop: bool) -> None:
    kill_local_playback()
    if loop:
        # Drive the loop from Python so the path never touches a shell.
        inner = (
            "import subprocess, sys\n"
            "while True:\n"
            "    if subprocess.run(['afplay', sys.argv[1]]).returncode != 0:\n"
            "        break\n"
        )
        cmd = [sys.executable, "-c", inner, str(path)]
    else:
        cmd = ["afplay", str(path)]
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,  # own process group, so killpg stops the loop
    )
    MUSIC_PID_FILE.write_text(str(proc.pid))


def resolve_uri(target: str | None, uri_flag: str | None) -> str | None:
    if uri_flag:
        return uri_flag
    if target:
        if target in MUSIC_PRESETS:
            return MUSIC_PRESETS[target]
        if target.startswith("spotify:"):
            return target
        sys.exit(
            f"focus: unknown preset '{target}'. "
            f"Available: {', '.join(MUSIC_PRESETS)}. Or pass a spotify:... URI."
        )
    return os.environ.get("FOCUS_SPOTIFY_URI")


def cmd_music(args: argparse.Namespace) -> int:
    if args.list:
        width = max(len(name) for name in MUSIC_PRESETS)
        for name, uri in MUSIC_PRESETS.items():
            print(f"  {name:<{width}}  {uri}")
        return 0

    if args.stop:
        spotify_pause()
        kill_local_playback()
        print("focus: music stopped")
        return 0

    if args.file:
        path = Path(args.file).expanduser()
        if not path.exists():
            sys.exit(f"focus: audio file not found: {path}")
        start_local_playback(path, loop=args.loop)
        print(f"focus: playing {path}" + (" (looped)" if args.loop else ""))
        return 0

    uri = resolve_uri(args.target, args.uri)
    if not uri:
        sys.exit(
            "focus: no music source. Pass a preset name, --uri, --file, "
            "or set FOCUS_SPOTIFY_URI. See `focus music --list`."
        )
    spotify_play(uri)
    print(f"focus: playing {uri}")
    return 0


# --- pomodoro -----------------------------------------------------------------

def notify(title: str, text: str, sound: str = "Glass") -> None:
    t = _escape_applescript(text)
    h = _escape_applescript(title)
    s = _escape_applescript(sound)
    osascript(f'display notification "{t}" with title "{h}" sound name "{s}"')


def read_pomodoro_state() -> dict | None:
    if not POMODORO_STATE_FILE.exists():
        return None
    try:
        return json.loads(POMODORO_STATE_FILE.read_text())
    except (json.JSONDecodeError, OSError):
        return None


def pomodoro_phase(state: dict, now: float | None = None) -> tuple[str, float]:
    now = now if now is not None else time.time()
    if now < state["work_end"]:
        return "work", state["work_end"] - now
    if now < state["break_end"]:
        return "break", state["break_end"] - now
    return "done", 0.0


def _clear_pomodoro_state() -> None:
    """Nuke any leftover pomodoro state: unblock, stop music, delete state file."""
    _run_self("unblock", sudo=True)
    _run_self("music", "--stop")
    POMODORO_STATE_FILE.unlink(missing_ok=True)


def cmd_pomodoro_start(args: argparse.Namespace) -> int:
    existing = read_pomodoro_state()
    if existing is not None:
        if _pid_alive(existing.get("pid", -1)):
            sys.exit("focus: a pomodoro is already running. Stop it first.")
        # Stale state file (daemon died / reboot). Recover and proceed.
        print("focus: clearing stale pomodoro state from previous session")
        _clear_pomodoro_state()

    now = time.time()
    work_end = now + args.work * 60
    break_end = work_end + args.break_ * 60
    music = args.music or os.environ.get("FOCUS_SPOTIFY_URI", "")

    # Write state BEFORE forking so `pomodoro stop` has something to read
    # even if invoked in the tiny window right after start. PID is patched in.
    state = {
        "goal": args.goal,
        "pid": 0,
        "started_at": now,
        "work_end": work_end,
        "break_end": break_end,
        "music": music,
    }
    POMODORO_STATE_FILE.write_text(json.dumps(state))

    cmd = [
        *_SELF, "_pomodoro-run",
        "--goal", args.goal,
        "--work-end", str(work_end),
        "--break-end", str(break_end),
    ]
    if music:
        cmd += ["--music", music]

    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    state["pid"] = proc.pid
    POMODORO_STATE_FILE.write_text(json.dumps(state))

    print(
        f"focus: pomodoro started — {args.work}min work, "
        f"{args.break_}min break — {args.goal}"
    )
    return 0


def cmd_pomodoro_run(args: argparse.Namespace) -> int:
    """Hidden. The actual daemon. Runs detached from the parent."""
    # Clean termination on SIGTERM so our finally block runs.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        blocked = _run_self("block", sudo=True) == 0
        if args.music:
            _run_self("music", args.music)
        notify(
            "Pomodoro started",
            args.goal + ("" if blocked else "\n(couldn't block websites)"),
        )
        # Work phase.
        time.sleep(max(0.0, args.work_end - time.time()))
        notify("Pomodoro complete", f"Finished: {args.goal}\nBreak time.")
        # Break phase. Block + music keep running through the break.
        time.sleep(max(0.0, args.break_end - time.time()))
        notify("Break over", "Ready for another session?")
    finally:
        _clear_pomodoro_state()
    return 0


def cmd_pomodoro_stop(args: argparse.Namespace) -> int:
    state = read_pomodoro_state()
    if state is None:
        print("focus: no pomodoro running")
        return 0
    pid = state.get("pid", 0)
    if pid and _pid_alive(pid):
        try:
            os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
        # Give the daemon a moment to clean up after itself.
        for _ in range(10):
            time.sleep(0.1)
            if not POMODORO_STATE_FILE.exists():
                break
    # If the daemon didn't (or couldn't) clean up, do it ourselves.
    if POMODORO_STATE_FILE.exists():
        _clear_pomodoro_state()
    print("focus: pomodoro stopped")
    return 0


def cmd_pomodoro_status(args: argparse.Namespace) -> int:
    state = read_pomodoro_state()
    if state is None:
        if args.json:
            print(json.dumps({"running": False}))
        else:
            print("focus: no pomodoro running")
        return 0
    phase, time_left = pomodoro_phase(state)
    if args.json:
        print(json.dumps({
            "running": True,
            "goal": state["goal"],
            "phase": phase,
            "time_left": round(time_left),
            "work_end": state["work_end"],
            "break_end": state["break_end"],
        }))
    else:
        mins, secs = divmod(int(time_left), 60)
        print(f"focus: {phase} — {mins}:{secs:02d} left — {state['goal']}")
    return 0


# --- entrypoint ---------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="focus",
        description="Block distractions and play focus music on macOS.",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("block", help="block sites from block.txt (needs sudo)")
    b.add_argument("-f", "--file", default=str(DEFAULT_BLOCK_FILE))
    b.set_defaults(func=cmd_block)

    u = sub.add_parser("unblock", help="remove the block (needs sudo)")
    u.set_defaults(func=cmd_unblock)

    t = sub.add_parser("toggle", help="block if inactive, unblock if active (needs sudo)")
    t.add_argument("-f", "--file", default=str(DEFAULT_BLOCK_FILE))
    t.add_argument("--json", action="store_true", help="machine-readable output")
    t.set_defaults(func=cmd_toggle)

    s = sub.add_parser("status", help="show current block status")
    s.add_argument("--json", action="store_true", help="machine-readable output")
    s.set_defaults(func=cmd_status)

    m = sub.add_parser("music", help="play or stop focus music")
    m.add_argument("target", nargs="?",
                   help="preset name (see --list) or a spotify: URI")
    m.add_argument("--uri", help="Spotify URI (overrides target / FOCUS_SPOTIFY_URI)")
    m.add_argument("--file", help="local audio file to play with afplay")
    m.add_argument("--loop", action="store_true", help="loop the local file")
    m.add_argument("--stop", action="store_true", help="pause Spotify and stop afplay")
    m.add_argument("--list", action="store_true", help="show available presets")
    m.set_defaults(func=cmd_music)

    po = sub.add_parser("pomodoro", help="run a pomodoro session with block + music")
    po_sub = po.add_subparsers(dest="pomodoro_cmd", required=True)

    po_start = po_sub.add_parser("start", help="start a pomodoro in the background")
    po_start.add_argument("goal", help="what you're working on")
    po_start.add_argument("--work", type=positive_int, default=25, metavar="MINS",
                          help="work minutes (default 25)")
    po_start.add_argument("--break", dest="break_", type=positive_int, default=5,
                          metavar="MINS", help="break minutes (default 5)")
    po_start.add_argument("--music", help="music preset or spotify: URI (default FOCUS_SPOTIFY_URI)")
    po_start.set_defaults(func=cmd_pomodoro_start)

    po_stop = po_sub.add_parser("stop", help="cancel the running pomodoro")
    po_stop.set_defaults(func=cmd_pomodoro_stop)

    po_status = po_sub.add_parser("status", help="show current pomodoro state")
    po_status.add_argument("--json", action="store_true", help="machine-readable output")
    po_status.set_defaults(func=cmd_pomodoro_status)

    # Hidden: the detached daemon invocation.
    run = sub.add_parser("_pomodoro-run", help=argparse.SUPPRESS)
    run.add_argument("--goal", required=True)
    run.add_argument("--work-end", dest="work_end", type=float, required=True)
    run.add_argument("--break-end", dest="break_end", type=float, required=True)
    run.add_argument("--music", default="")
    run.set_defaults(func=cmd_pomodoro_run)

    return p


def main() -> int:
    args = build_parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
