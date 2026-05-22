import Foundation

struct FrecencyEntry: Identifiable, Codable, Hashable {
    var id: String { path }
    let path: String
    var accumulatedScore: Double
    var lastVisit: Date
}
