#!/usr/bin/env python3
"""focus: block distracting websites and play focus music on macOS."""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
from pathlib import Path

HOSTS_FILE = Path("/etc/hosts")
HOSTS_BACKUP = Path("/etc/hosts.backup")
MARKER_START = "# === FOCUS BLOCK START ==="
MARKER_END = "# === FOCUS BLOCK END ==="
REDIRECT_IP = "127.0.0.1"

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_BLOCK_FILE = SCRIPT_DIR / "block.txt"
MUSIC_PID_FILE = Path.home() / ".focus-music.pid"


# --- website blocking ---------------------------------------------------------

def require_root() -> None:
    if os.geteuid() != 0:
        sys.exit("focus: this command needs sudo (it writes /etc/hosts)")


def read_block_list(path: Path) -> list[str]:
    sites: set[str] = set()
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        # Normalize: strip leading www. so both variants are always emitted below.
        sites.add(line.removeprefix("www."))
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


def cmd_block(args: argparse.Namespace) -> int:
    require_root()
    block_file = Path(args.file).expanduser()
    if not block_file.exists():
        sys.exit(f"focus: block file not found: {block_file}")

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
    print(f"focus: blocked {len(sites)} sites")
    return 0


def cmd_unblock(args: argparse.Namespace) -> int:
    require_root()
    HOSTS_FILE.write_text(strip_block_section(HOSTS_FILE.read_text()))
    flush_dns()
    print("focus: unblocked")
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
    rc = osascript(f'tell application "Spotify" to play track "{uri}"')
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
        cmd = ["sh", "-c", f'while true; do afplay "{path}"; done']
    else:
        cmd = ["afplay", str(path)]
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,  # own process group, so killpg stops the loop
    )
    MUSIC_PID_FILE.write_text(str(proc.pid))


def cmd_music(args: argparse.Namespace) -> int:
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

    uri = args.uri or os.environ.get("FOCUS_SPOTIFY_URI")
    if not uri:
        sys.exit(
            "focus: no music source. Pass --uri, --file, or set FOCUS_SPOTIFY_URI."
        )
    spotify_play(uri)
    print(f"focus: playing {uri}")
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

    s = sub.add_parser("status", help="show current block status")
    s.add_argument("--json", action="store_true", help="machine-readable output")
    s.set_defaults(func=cmd_status)

    m = sub.add_parser("music", help="play or stop focus music")
    m.add_argument("--uri", help="Spotify URI (overrides FOCUS_SPOTIFY_URI)")
    m.add_argument("--file", help="local audio file to play with afplay")
    m.add_argument("--loop", action="store_true", help="loop the local file")
    m.add_argument("--stop", action="store_true", help="pause Spotify and stop afplay")
    m.set_defaults(func=cmd_music)

    return p


def main() -> int:
    args = build_parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
