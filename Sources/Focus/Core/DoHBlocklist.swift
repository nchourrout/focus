import Foundation

/// Common DNS-over-HTTPS resolver endpoints. Browsers with "Secure DNS" enabled
/// query these directly over HTTPS, bypassing /etc/hosts and our site blocks.
/// Routing them to loopback forces the browser to fall back to the OS resolver
/// (which we already control via /etc/hosts).
///
/// Adding a new endpoint: pick the bare hostname only (no scheme, no path).
/// The `apply` path emits both `127.0.0.1` and `::1` rows, no www. variant.
enum DoHBlocklist {
    static let endpoints: [String] = [
        // Google
        "dns.google", "dns.google.com",
        // Cloudflare
        "cloudflare-dns.com",
        "mozilla.cloudflare-dns.com",
        "chrome.cloudflare-dns.com",
        "family.cloudflare-dns.com",
        "1.1.1.1.dns.cloudflare.com",
        // OpenDNS
        "doh.opendns.com",
        // Quad9
        "dns.quad9.net", "dns11.quad9.net",
        // AdGuard
        "dns.adguard.com", "dns.adguard-dns.com",
        // CleanBrowsing
        "doh.cleanbrowsing.org",
        // Apple iCloud Private Relay (also a DoH tunnel)
        "mask.icloud.com", "mask-h2.icloud.com",
    ]
}
