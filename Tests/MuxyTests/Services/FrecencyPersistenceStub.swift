import Foundation

@testable import Muxy

final class FrecencyPersistenceStub: FrecencyPersisting {
    var entries: [FrecencyEntry]
    var savedEntries: [FrecencyEntry]?

    init(initial: [FrecencyEntry] = []) {
        entries = initial
    }

    func loadEntries() throws -> [FrecencyEntry] {
        entries
    }

    func saveEntries(_ entries: [FrecencyEntry]) throws {
        savedEntries = entries
        self.entries = entries
    }
}
