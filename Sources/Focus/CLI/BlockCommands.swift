import ArgumentParser
import Foundation

struct Block: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "block",
        abstract: "block sites from block.txt (needs sudo)"
    )

    @Option(name: [.short, .customLong("file")], help: "Custom block list path.")
    var file: String?

    @Flag(inversion: .prefixedNo,
          help: "Also blackhole common DNS-over-HTTPS endpoints so browsers fall back to the system resolver.")
    var blockDoh: Bool = true

    func run() throws {
        try requireRoot()
        let url = try resolveBlockFile(file)
        let sites = try BlockList.load(from: url)
        if sites.isEmpty {
            throw CLIError.emptyBlockList(url)
        }
        let count = try HostsFile.apply(
            sites: sites,
            extraExactDomains: blockDoh ? DoHBlocklist.endpoints : []
        )
        print("focus: blocked \(count) sites")
    }
}

struct Unblock: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unblock",
        abstract: "remove the block (needs sudo)"
    )

    func run() throws {
        try requireRoot()
        try HostsFile.unblock()
        print("focus: unblocked")
    }
}

struct ToggleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "toggle",
        abstract: "block if inactive, unblock if active (needs sudo)"
    )

    @Option(name: [.short, .customLong("file")], help: "Custom block list path.")
    var file: String?

    @Flag(name: .customLong("json"), help: "Machine-readable output.")
    var json: Bool = false

    @Flag(inversion: .prefixedNo,
          help: "Also blackhole common DNS-over-HTTPS endpoints so browsers fall back to the system resolver.")
    var blockDoh: Bool = true

    func run() throws {
        try requireRoot()
        let nowActive: Bool
        if HostsFile.isActive() {
            try HostsFile.unblock()
            nowActive = false
        } else {
            let url = try resolveBlockFile(file)
            let sites = try BlockList.load(from: url)
            if sites.isEmpty { throw CLIError.emptyBlockList(url) }
            try HostsFile.apply(
                sites: sites,
                extraExactDomains: blockDoh ? DoHBlocklist.endpoints : []
            )
            nowActive = true
        }
        if json {
            printJSONActive(nowActive)
        } else {
            print("focus: " + (nowActive ? "blocked" : "unblocked"))
        }
    }
}

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "show current block status"
    )

    @Flag(name: .customLong("json"), help: "Machine-readable output.")
    var json: Bool = false

    func run() {
        let active = HostsFile.isActive()
        if json {
            printJSONActive(active)
        } else {
            print("focus: blocking is " + (active ? "ACTIVE" : "INACTIVE"))
        }
    }
}
