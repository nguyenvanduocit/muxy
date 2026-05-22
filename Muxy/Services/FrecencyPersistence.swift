import Foundation

protocol FrecencyPersisting {
    func loadEntries() throws -> [FrecencyEntry]
    func saveEntries(_ entries: [FrecencyEntry]) throws
}

final class FileFrecencyPersistence: FrecencyPersisting {
    private let store: CodableFileStore<[FrecencyEntry]>

    init(fileURL: URL = MuxyFileStorage.fileURL(filename: "frecency.json")) {
        store = CodableFileStore(fileURL: fileURL)
    }

    func loadEntries() throws -> [FrecencyEntry] {
        try store.load() ?? []
    }

    func saveEntries(_ entries: [FrecencyEntry]) throws {
        try store.save(entries)
    }
}
