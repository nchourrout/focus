import Testing
@testable import Focus

@Suite struct BrowserTabsTests {
    /// Reloading a tab only helps when the block covers its host, so the hosts
    /// handed to the script must be exactly the ones SiteBlock writes.
    @Test func blockedHostsMatchWhatSiteBlockWrites() {
        let sites = ["youtube.com"]
        let rendered = SiteBlock.renderBlock(sites: sites, extraExactDomains: [])
        let written = Set(rendered.split(separator: "\n")
            .filter { $0.hasPrefix(SiteBlock.redirectIP + " ") }
            .map { String($0.split(separator: " ")[1]) })
        #expect(Set(BrowserTabs.blockedHosts(for: sites)) == written)
        #expect(!BrowserTabs.blockedHosts(for: sites).contains("music.youtube.com"))
    }
}
