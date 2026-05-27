# Security Policy

Thanks for taking the time to make Focus safer.

## Scope

Focus runs privileged operations: it edits `/etc/hosts` via `sudo`, installs a
drop-in at `/etc/sudoers.d/focus` granting passwordless sudo for a fixed set
of subcommands, and forks a long-running pomodoro daemon. Anything that could
let an unprivileged process escalate via those paths, write outside the
documented allowlist, or hijack the menu bar app to run code as root is in
scope.

Out of scope: missing notarization / code signing (the app is intentionally
unsigned), Gatekeeper warnings on first launch, and behavior on jailbroken
or developer-mode systems.

## Reporting a vulnerability

Please **do not** open a public GitHub issue. Use GitHub's private vulnerability
reporting instead:

1. Go to https://github.com/nchourrout/focus/security/advisories
2. Click **Report a vulnerability**
3. Describe the issue, ideally with a reproduction and an affected version
   (the `VERSION` file in the repo root, or the tag of the release you saw it
   on).

I'll acknowledge within a week and aim to ship a fix or a clear mitigation in
the next release. If a fix needs coordination, the advisory thread is where
we'll work it out.

If GitHub's private reporting is unavailable to you for some reason, open an
issue titled "security: please contact me" with no details, and I'll reach
out.
