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

## Example dialogue

> **Dev**: When the user clicks Toggle in the menu bar, what happens?
> **You**: UI spawns `sudo focus toggle`. The CLI loads the **block list**, then
> calls `SiteBlock.toggle` with those sites. **SiteBlock** flips state: if
> already active, it deactivates; otherwise it activates the sites plus the
> **DoH endpoints**.

> **Dev**: Where does the DoH list live?
> **You**: Inside **SiteBlock**. They're part of how the block stays effective,
> not user data, so they're not in the **block list**.
