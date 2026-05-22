import Foundation

@MainActor
protocol FrecencyRecording {
    func recordVisit(path: String)
}
