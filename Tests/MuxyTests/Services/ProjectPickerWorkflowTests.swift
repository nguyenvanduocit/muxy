import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("ProjectPickerWorkflow")
struct ProjectPickerWorkflowTests {
    @Test("new browse input applies only latest directory snapshot")
    func latestDirectorySnapshotWins() async {
        let (preferences, cleanup) = makePreferences(.browse)
        defer { cleanup() }
        let loader = ProjectPickerWorkflowTestDirectoryLoader()
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences,
            directoryLoader: { await loader.load($0) },
            reloadDelay: .zero,
            loadingMessageDelay: .seconds(5)
        )

        workflow.setBrowseInput("~/First")
        await waitUntil { await loader.hasRequest(for: "~/First") }

        workflow.setBrowseInput("~/Second")
        await waitUntil { await loader.hasRequest(for: "~/Second") }

        await loader.resolve(
            input: "~/Second",
            snapshot: ProjectPickerDirectorySnapshot(rows: ["Second"], readFailed: false)
        )
        await waitUntil { workflow.session.browse.directoryItems.map(\.name) == ["Second"] }

        await loader.resolve(
            input: "~/First",
            snapshot: ProjectPickerDirectorySnapshot(rows: ["First"], readFailed: false)
        )
        try? await Task.sleep(for: .milliseconds(20))

        #expect(workflow.session.browse.directoryItems.map(\.name) == ["Second"])
    }

    @Test("loading message appears only while reload is active")
    func loadingMessagePolicy() async {
        let (slowPrefs, slowCleanup) = makePreferences(.browse)
        defer { slowCleanup() }
        let (fastPrefs, fastCleanup) = makePreferences(.browse)
        defer { fastCleanup() }
        let loader = ProjectPickerWorkflowTestDirectoryLoader()
        let slowWorkflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/Slow",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: slowPrefs,
            directoryLoader: { await loader.load($0) },
            reloadDelay: .zero,
            loadingMessageDelay: .milliseconds(10)
        )

        slowWorkflow.setBrowseInput("~/Slow")
        await waitUntil { await loader.hasRequest(for: "~/Slow") }
        await waitUntil { slowWorkflow.session.browse.directoryLoadState.showsMessage }
        #expect(slowWorkflow.session.browse.directoryLoadState == .loading(showsMessage: true))

        let fastWorkflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/Fast",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: fastPrefs,
            directoryLoader: { _ in ProjectPickerDirectorySnapshot(rows: ["Fast"], readFailed: false) },
            reloadDelay: .zero,
            loadingMessageDelay: .milliseconds(50)
        )

        fastWorkflow.setBrowseInput("~/Fast")
        await waitUntil { fastWorkflow.session.browse.directoryLoadState == .loaded }
        try? await Task.sleep(for: .milliseconds(80))

        #expect(fastWorkflow.session.browse.directoryLoadState == .loaded)
    }

    @Test("cancel invalidates load token and ignores pending snapshot")
    func cancelStopsPendingReloadWork() async {
        let (preferences, cleanup) = makePreferences(.browse)
        defer { cleanup() }
        let loader = ProjectPickerWorkflowTestDirectoryLoader()
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/Canceled",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences,
            directoryLoader: { await loader.load($0) },
            reloadDelay: .zero,
            loadingMessageDelay: .seconds(5)
        )

        workflow.setBrowseInput("~/Canceled")
        await waitUntil { await loader.hasRequest(for: "~/Canceled") }
        workflow.cancel()
        await loader.resolve(
            input: "~/Canceled",
            snapshot: ProjectPickerDirectorySnapshot(rows: ["Canceled"], readFailed: false)
        )
        try? await Task.sleep(for: .milliseconds(20))

        #expect(workflow.session.browse.directoryItems.isEmpty)
        #expect(workflow.session.browse.directoryLoadState == .idle)
    }

    @Test("typed path confirmation emits external requests")
    func typedPathConfirmationRequests() throws {
        let (existingPrefs, existingCleanup) = makePreferences(.browse)
        defer { existingCleanup() }
        let (missingPrefs, missingCleanup) = makePreferences(.browse)
        defer { missingCleanup() }
        let existingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-project-picker-workflow-existing-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: existingPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: existingPath) }

        let existingWorkflow = ProjectPickerWorkflow(
            defaultDisplayPath: existingPath.path,
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: existingPrefs
        )
        #expect(existingWorkflow.handle(.confirmTypedPath) == [
            .confirmProjectPath(path: existingPath.path, createIfMissing: false),
        ])

        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-project-picker-workflow-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
            .path
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: missingPath,
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: missingPrefs
        )

        #expect(workflow.handle(.confirmTypedPath) == [.askCreateDirectory(path: missingPath)])
        #expect(workflow.handleCreateDirectoryDecision(path: missingPath, accepted: false) == [])
        #expect(workflow.handleCreateDirectoryDecision(path: missingPath, accepted: true) == [
            .confirmProjectPath(path: missingPath, createIfMissing: true),
        ])
    }

    @Test("typed path confirmation is ignored in recent mode")
    func typedPathConfirmationIgnoredInRecentMode() {
        let (preferences, cleanup) = makePreferences(.recent)
        defer { cleanup() }
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences
        )

        #expect(workflow.handle(.confirmTypedPath) == [])
    }

    @Test("confirmation result requests dismissal or failure presentation")
    func confirmationResultHandling() {
        let (preferences, cleanup) = makePreferences(.browse)
        defer { cleanup() }
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences
        )

        #expect(workflow.handleProjectPathConfirmationResult(.success, path: "/tmp/muxy") == [.dismiss])
        #expect(workflow.handleProjectPathConfirmationResult(.notDirectory, path: "/tmp/muxy") == [
            .showFailure(ProjectPickerConfirmationFailurePresentation(result: .notDirectory, path: "/tmp/muxy")),
        ])
    }

    @Test("finder and settings actions emit edge requests")
    func edgeSideEffectRequests() {
        let (preferences, cleanup) = makePreferences(.browse)
        defer { cleanup() }
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences
        )

        #expect(workflow.chooseWithFinder() == [.dismiss, .chooseFinder])
        #expect(workflow.editDefaultLocation() == [.dismiss, .openSettingsFocusedOnDefaultLocation])
    }

    @Test("appear populates recent rows regardless of mode")
    func appearPopulatesRecentRows() {
        let (preferences, cleanup) = makePreferences(.recent)
        defer { cleanup() }
        let path = "/Users/alice/work/api"
        let store = makeFrecencyStore(initial: [
            FrecencyEntry(path: path, accumulatedScore: 1, lastVisit: Date()),
        ])
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: store,
            preferences: preferences,
            directoryLoader: { _ in ProjectPickerDirectorySnapshot(rows: [String](), readFailed: false) }
        )

        workflow.appear()

        #expect(workflow.session.recent.rows.first?.path == path)
    }

    @Test("appear initializes mode from preferences")
    func appearInitializesModeFromPreferences() {
        let (preferences, cleanup) = makePreferences(.recent)
        defer { cleanup() }
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences
        )

        #expect(workflow.session.mode == .recent)
    }

    @Test("activating a recent row emits a frecency confirm request")
    func activatingRecentRowEmitsConfirmRequest() {
        let (preferences, cleanup) = makePreferences(.recent)
        defer { cleanup() }
        let path = "/Users/alice/work/api"
        let store = makeFrecencyStore(initial: [
            FrecencyEntry(path: path, accumulatedScore: 1, lastVisit: Date()),
        ])
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: store,
            preferences: preferences,
            directoryLoader: { _ in ProjectPickerDirectorySnapshot(rows: [String](), readFailed: false) }
        )
        workflow.appear()

        #expect(workflow.activateRecentRow(at: 0) == [
            .confirmFrecencyPath(path: path),
        ])
    }

    @Test("openHighlighted on a recent row emits a frecency confirm request")
    func openHighlightedOnRecentRow() {
        let (preferences, cleanup) = makePreferences(.recent)
        defer { cleanup() }
        let path = "/Users/alice/work/api"
        let store = makeFrecencyStore(initial: [
            FrecencyEntry(path: path, accumulatedScore: 1, lastVisit: Date()),
        ])
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: store,
            preferences: preferences,
            directoryLoader: { _ in ProjectPickerDirectorySnapshot(rows: [String](), readFailed: false) }
        )
        workflow.appear()
        workflow.selectRecentRow(at: 0)

        #expect(workflow.handle(.openHighlighted) == [
            .confirmFrecencyPath(path: path),
        ])
    }

    @Test("completeHighlighted is a no-op in recent mode")
    func completeHighlightedNoOpInRecent() {
        let (preferences, cleanup) = makePreferences(.recent)
        defer { cleanup() }
        let path = "/Users/alice/work/api"
        let store = makeFrecencyStore(initial: [
            FrecencyEntry(path: path, accumulatedScore: 1, lastVisit: Date()),
        ])
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: store,
            preferences: preferences,
            directoryLoader: { _ in ProjectPickerDirectorySnapshot(rows: [String](), readFailed: false) }
        )
        workflow.appear()
        workflow.selectRecentRow(at: 0)
        let beforeBrowseInput = workflow.session.browse.input

        #expect(workflow.handle(.completeHighlighted) == [])
        #expect(workflow.session.browse.input == beforeBrowseInput)
    }

    @Test("frecency confirmation dismisses on success")
    func frecencyConfirmationSuccessDismisses() {
        let (preferences, cleanup) = makePreferences(.browse)
        defer { cleanup() }
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences
        )

        #expect(workflow.handleFrecencyConfirmationResult(.success, path: "/Users/alice/work/api") == [.dismiss])
    }

    @Test("frecency confirmation offers removal when the folder is missing")
    func frecencyConfirmationMissingOffersRemoval() {
        let (preferences, cleanup) = makePreferences(.browse)
        defer { cleanup() }
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences
        )

        #expect(workflow.handleFrecencyConfirmationResult(.missingDirectory, path: "/Users/alice/work/api") == [
            .askRemoveStaleFrecency(path: "/Users/alice/work/api"),
        ])
    }

    @Test("frecency confirmation surfaces a failure for non-missing errors")
    func frecencyConfirmationOtherErrorShowsFailure() {
        let (preferences, cleanup) = makePreferences(.browse)
        defer { cleanup() }
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences
        )

        #expect(workflow.handleFrecencyConfirmationResult(.notDirectory, path: "/Users/alice/work/api") == [
            .showFailure(ProjectPickerConfirmationFailurePresentation(result: .notDirectory, path: "/Users/alice/work/api")),
        ])
    }

    @Test("accepting stale frecency removal deletes the entry and refreshes only recent rows")
    func acceptingStaleFrecencyRemovalDeletesEntry() {
        let (preferences, cleanup) = makePreferences(.recent)
        defer { cleanup() }
        let stalePath = "/Users/alice/work/api"
        let store = makeFrecencyStore(initial: [
            FrecencyEntry(path: stalePath, accumulatedScore: 1, lastVisit: Date()),
        ])
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: store,
            preferences: preferences,
            directoryLoader: { _ in ProjectPickerDirectorySnapshot(rows: [String](), readFailed: false) }
        )
        workflow.appear()
        #expect(workflow.session.recent.rows.map(\.path) == [stalePath])

        #expect(workflow.handleRemoveStaleFrecencyDecision(path: stalePath, accepted: true) == [])

        #expect(store.entries.isEmpty)
        #expect(workflow.session.recent.rows.isEmpty)
    }

    @Test("declining stale frecency removal keeps the entry")
    func decliningStaleFrecencyRemovalKeepsEntry() {
        let (preferences, cleanup) = makePreferences(.recent)
        defer { cleanup() }
        let stalePath = "/Users/alice/work/api"
        let store = makeFrecencyStore(initial: [
            FrecencyEntry(path: stalePath, accumulatedScore: 1, lastVisit: Date()),
        ])
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: store,
            preferences: preferences
        )

        #expect(workflow.handleRemoveStaleFrecencyDecision(path: stalePath, accepted: false) == [])
        #expect(store.entries.map(\.path) == [stalePath])
    }

    @Test("activating a browse row schedules a directory reload for the descended path")
    func activatingBrowseRowSchedulesReload() async {
        let (preferences, cleanup) = makePreferences(.browse)
        defer { cleanup() }
        let loader = ProjectPickerWorkflowTestDirectoryLoader()
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/Projects/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences,
            directoryLoader: { await loader.load($0) },
            reloadDelay: .zero,
            loadingMessageDelay: .seconds(5)
        )
        workflow.appear()
        await waitUntil { await loader.hasRequest(for: "~/Projects/") }
        await loader.resolve(
            input: "~/Projects/",
            snapshot: ProjectPickerDirectorySnapshot(rows: ["muxy"], readFailed: false)
        )
        await waitUntil { workflow.session.browse.directoryItems.map(\.name) == ["muxy"] }

        _ = workflow.activateBrowseRow(at: 0)

        #expect(workflow.session.browse.input == "~/Projects/muxy/")
        await waitUntil { await loader.hasRequest(for: "~/Projects/muxy/") }
    }

    @Test("switching to recent persists the preference and refreshes recent rows")
    func switchToRecentPersistsAndRefreshes() {
        let (preferences, cleanup) = makePreferences(.browse)
        defer { cleanup() }
        let path = "/Users/alice/work/api"
        let store = makeFrecencyStore(initial: [
            FrecencyEntry(path: path, accumulatedScore: 1, lastVisit: Date()),
        ])
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: store,
            preferences: preferences,
            directoryLoader: { _ in ProjectPickerDirectorySnapshot(rows: [String](), readFailed: false) }
        )
        workflow.appear()

        workflow.setMode(.recent)

        #expect(workflow.session.mode == .recent)
        #expect(preferences.overlayMode == .recent)
        #expect(workflow.session.recent.rows.map(\.path) == [path])
    }

    @Test("recent filter change schedules no directory reload")
    func recentFilterDoesNotScheduleReload() async {
        let (preferences, cleanup) = makePreferences(.recent)
        defer { cleanup() }
        let loader = ProjectPickerWorkflowTestDirectoryLoader()
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences,
            directoryLoader: { await loader.load($0) },
            reloadDelay: .zero,
            loadingMessageDelay: .seconds(5)
        )
        workflow.appear()

        workflow.setRecentFilter("api")
        try? await Task.sleep(for: .milliseconds(20))

        #expect(await loader.requestCount == 0)
    }

    @Test("in-flight browse load resolves after switch to recent without altering recent state")
    func inFlightBrowseLoadAfterSwitchToRecent() async {
        let (preferences, cleanup) = makePreferences(.browse)
        defer { cleanup() }
        let loader = ProjectPickerWorkflowTestDirectoryLoader()
        let path = "/Users/alice/work/api"
        let store = makeFrecencyStore(initial: [
            FrecencyEntry(path: path, accumulatedScore: 1, lastVisit: Date()),
        ])
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/Projects/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: store,
            preferences: preferences,
            directoryLoader: { await loader.load($0) },
            reloadDelay: .zero,
            loadingMessageDelay: .seconds(5)
        )
        workflow.appear()
        await waitUntil { await loader.hasRequest(for: "~/Projects/") }

        workflow.setMode(.recent)
        await loader.resolve(
            input: "~/Projects/",
            snapshot: ProjectPickerDirectorySnapshot(rows: ["muxy"], readFailed: false)
        )
        try? await Task.sleep(for: .milliseconds(30))

        #expect(workflow.session.browse.directoryItems.isEmpty)
        #expect(workflow.session.browse.directoryLoadState == .idle)
        #expect(workflow.session.recent.rows.map(\.path) == [path])
    }

    @Test("recent rows are not capped at the rankedRows default of three")
    func recentRowsNotCappedAtThree() {
        let (preferences, cleanup) = makePreferences(.recent)
        defer { cleanup() }
        let lastVisit = Date()
        let entries = (0 ..< 6).map { index in
            FrecencyEntry(
                path: "/Users/alice/work/p\(index)",
                accumulatedScore: Double(6 - index),
                lastVisit: lastVisit
            )
        }
        let store = makeFrecencyStore(initial: entries)
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: store,
            preferences: preferences,
            directoryLoader: { _ in ProjectPickerDirectorySnapshot(rows: [String](), readFailed: false) }
        )

        workflow.appear()

        #expect(workflow.session.recent.rows.count == 6)
    }

    @Test("returning to browse after a failed load triggers a retry")
    func returningToBrowseRetriesFailedLoad() async {
        let (preferences, cleanup) = makePreferences(.browse)
        defer { cleanup() }
        let loader = ProjectPickerWorkflowTestDirectoryLoader()
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/Projects/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences,
            directoryLoader: { await loader.load($0) },
            reloadDelay: .zero,
            loadingMessageDelay: .seconds(5)
        )
        workflow.appear()
        await waitUntil { await loader.hasRequest(for: "~/Projects/") }
        await loader.resolve(
            input: "~/Projects/",
            snapshot: ProjectPickerDirectorySnapshot(rows: [String](), readFailed: true)
        )
        await waitUntil { workflow.session.browse.directoryLoadState == .failed }

        workflow.setMode(.recent)
        workflow.setMode(.browse)

        await waitUntil { await loader.requestCount == 2 }
        #expect(workflow.session.browse.directoryLoadState.isLoading)
    }

    @Test("appear in recent mode does not trigger a browse directory load")
    func appearInRecentModeDoesNotLoadDirectory() async {
        let (preferences, cleanup) = makePreferences(.recent)
        defer { cleanup() }
        let loader = ProjectPickerWorkflowTestDirectoryLoader()
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: makeFrecencyStore(),
            preferences: preferences,
            directoryLoader: { await loader.load($0) },
            reloadDelay: .zero,
            loadingMessageDelay: .seconds(5)
        )

        workflow.appear()
        try? await Task.sleep(for: .milliseconds(20))

        #expect(await loader.requestCount == 0)
        #expect(workflow.session.browse.directoryLoadState == .idle)
    }

    @Test("setProjectPaths refreshes recent rows and excludes newly added project paths")
    func setProjectPathsExcludesAddedPathsFromRecent() {
        let (preferences, cleanup) = makePreferences(.recent)
        defer { cleanup() }
        let path = "/Users/alice/work/api"
        let store = makeFrecencyStore(initial: [
            FrecencyEntry(path: path, accumulatedScore: 1, lastVisit: Date()),
        ])
        let workflow = ProjectPickerWorkflow(
            defaultDisplayPath: "~/",
            homeDirectory: "/Users/alice",
            projectPaths: [],
            frecencyStore: store,
            preferences: preferences,
            directoryLoader: { _ in ProjectPickerDirectorySnapshot(rows: [String](), readFailed: false) }
        )
        workflow.appear()
        #expect(workflow.session.recent.rows.map(\.path) == [path])

        workflow.setProjectPaths([path])

        #expect(workflow.session.recent.rows.isEmpty)
    }

    private func makeFrecencyStore(initial: [FrecencyEntry] = []) -> FrecencyStore {
        FrecencyStore(
            persistence: FrecencyPersistenceStub(initial: initial),
            homeDirectory: "/Users/alice"
        )
    }

    private func makePreferences(_ mode: ProjectPickerOverlayMode) -> (ProjectPickerPreferences, () -> Void) {
        let suiteName = "muxy.picker.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let preferences = ProjectPickerPreferences(defaults: defaults)
        preferences.overlayMode = mode
        return (preferences, { defaults.removePersistentDomain(forName: suiteName) })
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping () async -> Bool
    ) async {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

private actor ProjectPickerWorkflowTestDirectoryLoader {
    private var requests: [String] = []
    private var continuations: [String: CheckedContinuation<ProjectPickerDirectorySnapshot, Never>] = [:]

    func load(_ pathState: ProjectPickerPathState) async -> ProjectPickerDirectorySnapshot {
        requests.append(pathState.input)
        return await withCheckedContinuation { continuation in
            continuations[pathState.input] = continuation
        }
    }

    func hasRequest(for input: String) -> Bool {
        requests.contains(input)
    }

    var requestCount: Int { requests.count }

    func resolve(input: String, snapshot: ProjectPickerDirectorySnapshot) {
        continuations.removeValue(forKey: input)?.resume(returning: snapshot)
    }
}
