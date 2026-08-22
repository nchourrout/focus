import Testing
import Foundation
@testable import Focus

@Suite struct BlockStatusTests {

    // MARK: Wire format (frozen bytes; external scripts grep them)

    @Test func wireBytesAreUnchanged() {
        #expect(BlockStatus(active: true).wireFormat == "{\"active\": true}")
        #expect(BlockStatus(active: false).wireFormat == "{\"active\": false}")
    }

    // MARK: The decoder accepts what the CLI writes

    @Test func decoderReadsTheWireFormat() throws {
        let decoded = try JSONDecoder()
            .decode(BlockStatus.self, from: Data(BlockStatus(active: true).wireFormat.utf8))
        #expect(decoded.active == true)
    }

    @Test func decoderAlsoReadsCompactJSON() throws {
        // If emission ever moves to JSONEncoder, consumers must not notice.
        let decoded = try JSONDecoder().decode(BlockStatus.self, from: Data("{\"active\":false}".utf8))
        #expect(decoded.active == false)
    }

    // MARK: Round-trip through Codable itself

    @Test func codableRoundTripPreservesState() throws {
        let original = BlockStatus(active: true)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(BlockStatus.self, from: data).active == true)
    }
}
