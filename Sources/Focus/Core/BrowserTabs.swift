import Foundation

/// Reloads browser tabs that are open on a blocked site, right after the block
/// turns on.
///
/// The hosts file only acts on a new name lookup. A tab already open on
/// YouTube when a work phase starts keeps working: the page is a single-page
/// app that never navigates, and the video streams from googlevideo.com, which
/// isn't on the list. A reload makes the browser resolve the host again, which
/// now lands on loopback, so the tab shows its error page.
///
/// Runs as the user (never under sudo) because it talks to the browsers over
/// Apple Events. The first time, macOS asks whether Focus may control each
/// browser; a refusal just leaves those tabs alone.
enum BrowserTabs {
    /// Every hostname the block covers for `sites`, matching what SiteBlock
    /// writes to /etc/hosts. A tab on any other host (music.youtube.com) still
    /// resolves after a reload, so reloading it would only cost the user their
    /// place.
    static func blockedHosts(for sites: [String]) -> [String] {
        sites.flatMap { site in
            SiteBlock.hostPrefixes.map { ($0 + site).lowercased() }
        }
    }

    /// Reload tabs on the user's block list, without waiting for it. A list that
    /// fails to load is skipped: the block command reads the same file and will
    /// have failed on it already.
    static func reloadBlockedTabs() {
        guard let sites = try? BlockList.load(from: resolveBlockFile(nil)) else { return }
        reload(hosts: blockedHosts(for: sites))
    }

    static func reload(hosts: [String]) {
        guard !hosts.isEmpty,
              let json = try? JSONSerialization.data(withJSONObject: hosts),
              let arg = String(data: json, encoding: .utf8) else { return }
        do {
            try Shell.spawn(Shell.Command(
                path: "/usr/bin/osascript", ["-l", "JavaScript", "-e", script, arg]
            ))
        } catch {
            Log.actions.error("tab reload failed to launch: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// JXA: walk every tab of each running browser and reload the ones whose
    /// host is blocked. `running()` doesn't launch a browser that is closed.
    /// The one-second delay gives the browser time to notice the new hosts
    /// file before the reload asks it to resolve again. Safari has no reload
    /// command, so setting a tab's URL to itself stands in for one. Every
    /// browser is wrapped on its own, so one that refuses Apple Events or
    /// doesn't speak this dictionary doesn't stop the rest.
    static let script = #"""
    function run(argv) {
        const hosts = new Set(JSON.parse(argv[0]));
        const hostOf = (u) => {
            const m = /^https?:\/\/([^\/?#:]+)/i.exec(u || "");
            return m ? m[1].toLowerCase().replace(/\.$/, "") : null;
        };
        const safari = ["com.apple.Safari"];
        const chromium = [
            "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser",
            "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "company.thebrowser.Browser",
        ];
        delay(1);
        let reloaded = 0;
        for (const id of chromium.concat(safari)) {
            try {
                const app = Application(id);
                if (!app.running()) continue;
                for (const w of app.windows()) {
                    let urls;
                    try { urls = w.tabs.url(); } catch (e) { continue; }
                    urls.forEach((u, i) => {
                        if (!hosts.has(hostOf(u))) return;
                        try {
                            if (safari.includes(id)) { w.tabs[i].url = u; } else { w.tabs[i].reload(); }
                            reloaded++;
                        } catch (e) {}
                    });
                }
            } catch (e) {}
        }
        return String(reloaded);
    }
    """#
}
