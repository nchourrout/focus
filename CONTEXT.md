# Focus

A macOS menu bar Pomodoro timer that also blocks distracting sites by editing
`/etc/hosts`. Single Swift binary that runs as either CLI or menu bar app.

## Language

**SiteBlock**:
The mechanism that prevents browsers from reaching configured sites by writing
a marker-delimited section into `/etc/hosts`, blackholing each hostname to
loopback, and flushing the DNS cache. Owns the recipe end to end; mutation
requires root.
_Avoid_: hosts blocker, ad blocker, firewall.

**Block list**:
The user's list of sites they want blocked when SiteBlock is active. Loaded
from `~/Library/Application Support/Focus/block.txt`. A list of hostnames, not
the act of blocking.
_Avoid_: blocklist (one word), denylist, blacklist.

**DoH endpoints**:
DNS-over-HTTPS resolver hostnames (e.g. `dns.google`) that SiteBlock also routes
to loopback so browsers fall back to the OS resolver. Internal to SiteBlock.
_Avoid_: secure DNS, DoH servers.

**PomodoroSession**:
The module that owns one user's pomodoro lifecycle: persistence, deadline math,
phase derivation, and (later) transition events. One on-disk record at a time.
_Avoid_: timer, pomodoro manager.

**Active session**:
A pomodoro currently in progress (or just finished and not yet cleared). A
`PomodoroSession.Active` carries goal, pid, deadlines, music, block flag.
_Avoid_: running pomodoro, current state.

**Phase**:
Which part of an Active session is currently underway: `work`, `break`, or
`done`. Derived from deadlines, not stored.
_Avoid_: stage, step.

**Station**:
One source of focus audio: a curated preset, an arbitrary http(s) stream, or a
local audio file. The value that flows wherever music goes. Constructing one is
the only place a stream's scheme is checked, and it owns both on-disk
encodings: the resolved `uri` the state file and `--music` argv carry, and the
`label` the music PID file carries.
_Avoid_: track, song, source, music string.

**PomodoroPlan**:
Everything fixed for the duration of one run: goal, work and break minutes,
whether to block, and which Station plays. Assembled in exactly one place, from
Settings plus explicit overrides, so the CLI and the menu bar start identical
sessions.
_Avoid_: config, options, settings (that word belongs to the Settings window).

**Cadence**:
The long-break rhythm plus whether the run keeps cycling at all: long-break
length, sessions per set, keep-cycling, stop-after-set. Deliberately separate
from the PomodoroPlan because its timing differs — the plan is fixed for the
run, the cadence is re-read at every phase boundary so a mid-run Settings
change lands at the next transition.
_Avoid_: schedule, rhythm, policy.

**Set**:
A group of `sessionsBeforeLongBreak` work sessions. The boundary that earns the
long break, and where a "stop after each set" run ends and asks whether to
start another.
_Avoid_: round, cycle, batch.

**SessionRunner**:
The module that runs the loop inside the daemon process: sleep to the work
deadline, lift the block for the break, then stop or roll into the next
session. Everything it does to the outside world goes through `SessionEffects`,
which has a live adapter and a test fake with a virtual clock.
_Avoid_: engine, controller, manager.

## Example dialogue

> **Dev**: When the user clicks Toggle in the menu bar, what happens?
> **You**: UI spawns `sudo focus toggle`. The CLI loads the **block list**, then
> calls `SiteBlock.toggle` with those sites. **SiteBlock** flips state: if
> already active, it deactivates; otherwise it activates the sites plus the
> **DoH endpoints**.

> **Dev**: Where does the DoH list live?
> **You**: Inside **SiteBlock**. They're part of how the block stays effective,
> not user data, so they're not in the **block list**.

> **Dev**: I changed the long break to 20 minutes while a session was running.
> When does that apply?
> **You**: At the next boundary. Long-break length is part of the **Cadence**,
> which the **SessionRunner** re-reads every time it reaches a phase boundary.
> Work and break minutes wouldn't change — those are in the **PomodoroPlan**,
> fixed when the run started.

> **Dev**: The menu says "Music ♪ Groovesalad". Where does that name come from?
> **You**: The **Station**. Playback wrote its label to the music PID file; the
> menu reads it back and asks for `displayName`. Nothing along the way
> re-derives whether the label happens to be a preset.
