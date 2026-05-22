import Foundation

@testable import Muxy

@MainActor
final class FrecencyRecordingStub: FrecencyRecording {
    private(set) var recordedPaths: [String] = []

    func recordVisit(path: String) {
        recordedPaths.append(path)
    }
}
