import Foundation
import Testing

@testable import Muxy

@Suite("FrecencyStore")
@MainActor
struct FrecencyStoreTests {
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("recordVisit adds a new entry with score one")
    func recordVisitAddsEntry() throws {
        let directory = try TemporaryDirectory()
        let persistence = FrecencyPersistenceStub()
        let store = FrecencyStore(persistence: persistence, now: { self.reference })

        store.recordVisit(path: directory.path)

        let entry = try #require(store.entries.first)
        #expect(entry.path == directory.standardizedPath)
        #expect(entry.accumulatedScore == 1)
        #expect(persistence.savedEntries?.count == 1)
    }

    @Test("recordVisit increments an existing entry and decays before adding")
    func recordVisitIncrementsExistingEntry() throws {
        let directory = try TemporaryDirectory()
        let persistence = FrecencyPersistenceStub()
        let clock = MutableClock(reference)
        let store = FrecencyStore(persistence: persistence, now: { clock.current })

        store.recordVisit(path: directory.path)
        clock.current = reference.addingTimeInterval(FrecencyScoring.halfLifeDays * 86_400)
        store.recordVisit(path: directory.path)

        let entry = try #require(store.entries.first)
        #expect(abs(entry.accumulatedScore - 1.5) < 0.000_001)
    }

    @Test("rankedRows orders entries by decayed score")
    func rankedRowsOrdersByScore() throws {
        let recent = try TemporaryDirectory()
        let old = try TemporaryDirectory()
        let persistence = FrecencyPersistenceStub(initial: [
            FrecencyEntry(path: old.standardizedPath, accumulatedScore: 4, lastVisit: reference.addingTimeInterval(-90 * 86_400)),
            FrecencyEntry(path: recent.standardizedPath, accumulatedScore: 2, lastVisit: reference),
        ])
        let store = FrecencyStore(persistence: persistence, now: { self.reference })

        let rows = store.rankedRows(matching: "", limit: FrecencyStore.softCap)

        #expect(rows.map(\.path) == [recent.standardizedPath, old.standardizedPath])
    }

    @Test("rankedRows filters by case-insensitive basename substring")
    func rankedRowsFiltersByBasename() throws {
        let muxy = try TemporaryDirectory(name: "muxy-app")
        let other = try TemporaryDirectory(name: "sample-tool")
        let persistence = FrecencyPersistenceStub(initial: [
            FrecencyEntry(path: muxy.standardizedPath, accumulatedScore: 1, lastVisit: reference),
            FrecencyEntry(path: other.standardizedPath, accumulatedScore: 1, lastVisit: reference),
        ])
        let store = FrecencyStore(persistence: persistence, now: { self.reference })

        let rows = store.rankedRows(matching: "MUXY", limit: FrecencyStore.softCap)

        #expect(rows.map(\.path) == [muxy.standardizedPath])
    }

    @Test("rankedRows excludes paths in the exclude set")
    func rankedRowsExcludesPaths() throws {
        let open = try TemporaryDirectory()
        let available = try TemporaryDirectory()
        let persistence = FrecencyPersistenceStub(initial: [
            FrecencyEntry(path: open.standardizedPath, accumulatedScore: 5, lastVisit: reference),
            FrecencyEntry(path: available.standardizedPath, accumulatedScore: 1, lastVisit: reference),
        ])
        let store = FrecencyStore(persistence: persistence, now: { self.reference })

        let rows = store.rankedRows(matching: "", excluding: [open.standardizedPath], limit: FrecencyStore.softCap)

        #expect(rows.map(\.path) == [available.standardizedPath])
    }

    @Test("rankedRows respects the limit")
    func rankedRowsRespectsLimit() throws {
        let directories = try (0 ..< 5).map { _ in try TemporaryDirectory() }
        let persistence = FrecencyPersistenceStub(initial: directories.map {
            FrecencyEntry(path: $0.standardizedPath, accumulatedScore: 1, lastVisit: reference)
        })
        let store = FrecencyStore(persistence: persistence, now: { self.reference })

        #expect(store.rankedRows(matching: "", limit: 3).count == 3)
    }

    @Test("save prunes to the soft cap keeping the highest scores")
    func savePrunesToSoftCap() throws {
        let directory = try TemporaryDirectory()
        let persistence = FrecencyPersistenceStub(initial: (0 ..< FrecencyStore.softCap).map {
            FrecencyEntry(
                path: "/tmp/muxy-frecency-low-\($0)",
                accumulatedScore: 0.01,
                lastVisit: reference
            )
        })
        let store = FrecencyStore(persistence: persistence, now: { self.reference })

        store.recordVisit(path: directory.path)

        #expect(store.entries.count == FrecencyStore.softCap)
        #expect(store.entries.contains { $0.path == directory.standardizedPath })
    }

    @Test("persistence round-trip restores entries on load")
    func persistenceRoundTrip() throws {
        let directory = try TemporaryDirectory()
        let persistence = FrecencyPersistenceStub()
        let writer = FrecencyStore(persistence: persistence, now: { self.reference })
        writer.recordVisit(path: directory.path)

        let reader = FrecencyStore(persistence: persistence, now: { self.reference })

        #expect(reader.entries.map(\.path) == [directory.standardizedPath])
    }

    @Test("file persistence round-trip preserves entry fields through JSON")
    func filePersistenceRoundTrip() throws {
        let directory = try TemporaryDirectory()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-frecency-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let writer = FrecencyStore(persistence: FileFrecencyPersistence(fileURL: fileURL), now: { self.reference })
        writer.recordVisit(path: directory.path)

        let reader = FrecencyStore(persistence: FileFrecencyPersistence(fileURL: fileURL), now: { self.reference })

        let entry = try #require(reader.entries.first)
        #expect(entry.path == directory.standardizedPath)
        #expect(entry.accumulatedScore == 1)
        #expect(entry.lastVisit == reference)
    }

    @Test("remove deletes the matching entry and persists the change")
    func removeDeletesMatchingEntry() throws {
        let kept = try TemporaryDirectory()
        let removed = try TemporaryDirectory()
        let persistence = FrecencyPersistenceStub(initial: [
            FrecencyEntry(path: kept.standardizedPath, accumulatedScore: 1, lastVisit: reference),
            FrecencyEntry(path: removed.standardizedPath, accumulatedScore: 1, lastVisit: reference),
        ])
        let store = FrecencyStore(persistence: persistence, now: { self.reference })

        store.remove(path: removed.path)

        #expect(store.entries.map(\.path) == [kept.standardizedPath])
        #expect(persistence.savedEntries?.map(\.path) == [kept.standardizedPath])
    }

    @Test("remove ignores a path that is not stored")
    func removeIgnoresUnknownPath() throws {
        let kept = try TemporaryDirectory()
        let persistence = FrecencyPersistenceStub(initial: [
            FrecencyEntry(path: kept.standardizedPath, accumulatedScore: 1, lastVisit: reference),
        ])
        let store = FrecencyStore(persistence: persistence, now: { self.reference })

        store.remove(path: "/tmp/muxy-frecency-unknown-\(UUID().uuidString)")

        #expect(store.entries.map(\.path) == [kept.standardizedPath])
        #expect(persistence.savedEntries == nil)
    }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var current: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}

private final class TemporaryDirectory {
    let url: URL

    var path: String { url.path }
    var standardizedPath: String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    init(name: String? = nil) throws {
        let component = name.map { "\($0)-\(UUID().uuidString)" } ?? "muxy-frecency-\(UUID().uuidString)"
        url = FileManager.default.temporaryDirectory.appendingPathComponent(component, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
