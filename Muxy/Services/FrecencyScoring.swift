import Foundation

enum FrecencyScoring {
    static let halfLifeDays: Double = 30

    static func decayedScore(_ entry: FrecencyEntry, now: Date) -> Double {
        let ageDays = max(0, now.timeIntervalSince(entry.lastVisit)) / 86400
        return entry.accumulatedScore * pow(0.5, ageDays / halfLifeDays)
    }
}
