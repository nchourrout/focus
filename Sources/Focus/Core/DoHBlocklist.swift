import Foundation

/// Common DNS-over-HTTPS resolver endpoints. Browsers with "Secure DNS" enabled
/// query these directly over HTTPS, bypassing /etc/hosts and our site blocks.
/// Routing them to loopback forces the browser to fall back to the OS resolver
/// (which we already control via /etc/hosts).
enum DoHBlocklist {
    static let endpoints: [String] = [
        "dns.google", "dns.google.com",
        "cloudflare-dns.com",
        "mozilla.cloudflare-dns.com",
        "chrome.cloudflare-dns.com",
        "family.cloudflare-dns.com",
        "1.1.1.1.dns.cloudflare.com",
        "doh.opendns.com",
        "dns.quad9.net", "dns11.quad9.net",
        "dns.adguard.com", "dns.adguard-dns.com",
        "doh.cleanbrowsing.org",
        "mask.icloud.com", "mask-h2.icloud.com",
    ]
}
