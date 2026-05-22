import Foundation
import Testing

@testable import Muxy

@Suite("FrecencyScoring")
struct FrecencyScoringTests {
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("decayedScore returns the accumulated score when no time has passed")
    func decayedScoreWithoutAge() {
        let entry = FrecencyEntry(path: "/a", accumulatedScore: 4, lastVisit: reference)

        #expect(FrecencyScoring.decayedScore(entry, now: reference) == 4)
    }

    @Test("decayedScore halves the score after one half-life")
    func decayedScoreAfterHalfLife() {
        let entry = FrecencyEntry(path: "/a", accumulatedScore: 8, lastVisit: reference)
        let later = reference.addingTimeInterval(FrecencyScoring.halfLifeDays * 86_400)

        #expect(abs(FrecencyScoring.decayedScore(entry, now: later) - 4) < 0.000_001)
    }

    @Test("decayedScore quarters the score after two half-lives")
    func decayedScoreAfterTwoHalfLives() {
        let entry = FrecencyEntry(path: "/a", accumulatedScore: 8, lastVisit: reference)
        let later = reference.addingTimeInterval(2 * FrecencyScoring.halfLifeDays * 86_400)

        #expect(abs(FrecencyScoring.decayedScore(entry, now: later) - 2) < 0.000_001)
    }

    @Test("decayedScore clamps negative ages to the present")
    func decayedScoreClampsNegativeAge() {
        let entry = FrecencyEntry(path: "/a", accumulatedScore: 5, lastVisit: reference)
        let earlier = reference.addingTimeInterval(-86_400)

        #expect(FrecencyScoring.decayedScore(entry, now: earlier) == 5)
    }
}
