import Foundation
import os

private let logger = Logger(subsystem: "app.muxy", category: "FrecencyStore")

@MainActor
@Observable
final class FrecencyStore: FrecencyRecording {
    static let softCap = 50

    private(set) var entries: [FrecencyEntry] = []

    @ObservationIgnored private let persistence: any FrecencyPersisting
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let homeDirectory: String

    init(
        persistence: any FrecencyPersisting,
        now: @Sendable @escaping () -> Date = { Date() },
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.persistence = persistence
        self.now = now
        self.homeDirectory = homeDirectory
        load()
    }

    func recordVisit(path: String) {
        let standardizedPath = ProjectPickerPathService.standardizedPath(path)
        let timestamp = now()
        if let index = entries.firstIndex(where: { $0.path == standardizedPath }) {
            let decayed = FrecencyScoring.decayedScore(entries[index], now: timestamp)
            entries[index].accumulatedScore = decayed + 1
            entries[index].lastVisit = timestamp
        } else {
            entries.append(FrecencyEntry(
                path: standardizedPath,
                accumulatedScore: 1,
                lastVisit: timestamp
            ))
        }
        save()
    }

    func rankedRows(matching filter: String, excluding excludedPaths: Set<String> = [], limit: Int) -> [FrecencyRow] {
        let timestamp = now()
        let pathService = ProjectPickerPathService(homeDirectory: homeDirectory)
        let trimmedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let ranked = entries.sorted {
            FrecencyScoring.decayedScore($0, now: timestamp) > FrecencyScoring.decayedScore($1, now: timestamp)
        }
        var rows: [FrecencyRow] = []
        for entry in ranked {
            guard rows.count < limit else { break }
            guard !excludedPaths.contains(entry.path) else { continue }
            guard matchesFilter(entry.path, filter: trimmedFilter) else { continue }
            let url = URL(fileURLWithPath: entry.path)
            rows.append(FrecencyRow(
                path: entry.path,
                displayName: url.lastPathComponent,
                displayDirectory: pathService.abbreviatedDirectoryDisplayPath(url.deletingLastPathComponent().path)
            ))
        }
        return rows
    }

    func remove(path: String) {
        let standardizedPath = ProjectPickerPathService.standardizedPath(path)
        guard entries.contains(where: { $0.path == standardizedPath }) else { return }
        entries.removeAll { $0.path == standardizedPath }
        save()
    }

    private func matchesFilter(_ path: String, filter: String) -> Bool {
        guard !filter.isEmpty else { return true }
        return URL(fileURLWithPath: path).lastPathComponent.localizedCaseInsensitiveContains(filter)
    }

    private func save() {
        let entriesToPersist = prunedEntries()
        do {
            try persistence.saveEntries(entriesToPersist)
            entries = entriesToPersist
        } catch {
            logger.error("Failed to save frecency entries: \(error)")
        }
    }

    private func prunedEntries() -> [FrecencyEntry] {
        guard entries.count > Self.softCap else { return entries }
        let timestamp = now()
        return Array(
            entries
                .sorted { FrecencyScoring.decayedScore($0, now: timestamp) > FrecencyScoring.decayedScore($1, now: timestamp) }
                .prefix(Self.softCap)
        )
    }

    private func load() {
        do {
            entries = try persistence.loadEntries()
        } catch {
            logger.error("Failed to load frecency entries: \(error)")
        }
    }
}
