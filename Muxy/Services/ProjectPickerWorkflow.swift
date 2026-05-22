import Foundation

typealias ProjectPickerDirectoryLoader = @Sendable (ProjectPickerPathState) async -> ProjectPickerDirectorySnapshot

@MainActor
@Observable
final class ProjectPickerWorkflow {
    private(set) var session: ProjectPickerSession

    @ObservationIgnored private var directoryLoadID = UUID()
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var loadingMessageTask: Task<Void, Never>?
    @ObservationIgnored private let directoryLoader: ProjectPickerDirectoryLoader
    @ObservationIgnored private let frecencyStore: FrecencyStore
    @ObservationIgnored private let preferences: ProjectPickerPreferences
    @ObservationIgnored private let reloadDelay: Duration
    @ObservationIgnored private let loadingMessageDelay: Duration
    @ObservationIgnored private var didAppear = false
    @ObservationIgnored private var addedProjectPaths: Set<String> = []

    init(
        defaultDisplayPath: String = ProjectPickerDefaultLocation.state.displayPath,
        homeDirectory: String = NSHomeDirectory(),
        projectPaths: [String],
        frecencyStore: FrecencyStore,
        preferences: ProjectPickerPreferences = ProjectPickerPreferences(),
        directoryLoader: @escaping ProjectPickerDirectoryLoader = ProjectPickerWorkflow.liveDirectoryLoader,
        reloadDelay: Duration = .milliseconds(100),
        loadingMessageDelay: Duration = .milliseconds(500)
    ) {
        session = ProjectPickerSession(
            defaultDisplayPath: defaultDisplayPath,
            homeDirectory: homeDirectory,
            projectPaths: projectPaths,
            mode: preferences.overlayMode
        )
        self.preferences = preferences
        self.frecencyStore = frecencyStore
        self.directoryLoader = directoryLoader
        self.reloadDelay = reloadDelay
        self.loadingMessageDelay = loadingMessageDelay
        addedProjectPaths = Set(projectPaths.map(ProjectPickerPathService.standardizedPath))
    }

    deinit {
        reloadTask?.cancel()
        loadingMessageTask?.cancel()
    }

    func appear() {
        guard !didAppear else { return }
        didAppear = true
        refreshRecentRows()
        if session.mode == .browse {
            scheduleDirectoryReload(pathState: session.pathState)
        }
    }

    func cancel() {
        cancelDirectoryReload()
    }

    func setProjectPaths(_ projectPaths: [String]) {
        session.setProjectPaths(projectPaths)
        addedProjectPaths = Set(projectPaths.map(ProjectPickerPathService.standardizedPath))
        refreshRecentRows()
    }

    func setMode(_ newMode: ProjectPickerOverlayMode) {
        guard session.mode != newMode else { return }
        cancelDirectoryReload()
        session.setMode(newMode)
        preferences.overlayMode = newMode
        switch newMode {
        case .recent:
            refreshRecentRows()
        case .browse:
            if session.browse.directoryLoadState.needsLoad {
                scheduleDirectoryReload(pathState: session.pathState)
            }
        }
    }

    func setRecentFilter(_ filter: String) {
        session.setRecentFilter(filter)
        refreshRecentRows()
    }

    func setBrowseInput(_ input: String) {
        session.setBrowseInput(input)
        scheduleDirectoryReload(pathState: session.pathState)
    }

    func selectRecentRow(at index: Int) {
        session.selectRecentRow(at: index)
    }

    func selectBrowseRow(at index: Int) {
        session.selectBrowseRow(at: index)
    }

    func activateRecentRow(at index: Int) -> [ProjectPickerWorkflowRequest] {
        guard let activation = session.resolveRecentActivation(at: index) else { return [] }
        if case let .confirmPath(path) = activation { return [.confirmFrecencyPath(path: path)] }
        return []
    }

    func activateBrowseRow(at index: Int) -> [ProjectPickerWorkflowRequest] {
        let previousInput = session.browse.input
        guard let activation = session.activateBrowseRow(at: index) else { return [] }
        switch activation {
        case .descended:
            guard session.browse.input != previousInput else { return [] }
            scheduleDirectoryReload(pathState: session.pathState)
            return []
        case .confirmPath:
            return []
        }
    }

    func handle(_ command: ProjectPickerCommand) -> [ProjectPickerWorkflowRequest] {
        switch command {
        case .moveHighlightUp,
             .moveHighlightDown:
            session.handle(command)
            return []
        case .openHighlighted:
            return openHighlighted()
        case .goBack,
             .completeHighlighted:
            guard session.mode == .browse else { return [] }
            return reloadAfterBrowseInputChange {
                session.handle(command)
            }
        case .confirmTypedPath:
            guard session.mode == .browse else { return [] }
            return confirmTypedPath()
        case .switchToRecent:
            setMode(.recent)
            return []
        case .switchToBrowse:
            setMode(.browse)
            return []
        case .dismiss:
            return [.dismiss]
        }
    }

    func chooseWithFinder() -> [ProjectPickerWorkflowRequest] {
        [.dismiss, .chooseFinder]
    }

    func editDefaultLocation() -> [ProjectPickerWorkflowRequest] {
        [.dismiss, .openSettingsFocusedOnDefaultLocation]
    }

    func handleCreateDirectoryDecision(path: String, accepted: Bool) -> [ProjectPickerWorkflowRequest] {
        guard accepted else { return [] }
        return [.confirmProjectPath(path: path, createIfMissing: true)]
    }

    func handleProjectPathConfirmationResult(
        _ result: ProjectOpenConfirmationResult,
        path: String
    ) -> [ProjectPickerWorkflowRequest] {
        guard !result.didConfirm else { return [.dismiss] }
        return [.showFailure(ProjectPickerConfirmationFailurePresentation(result: result, path: path))]
    }

    func handleFrecencyConfirmationResult(
        _ result: ProjectOpenConfirmationResult,
        path: String
    ) -> [ProjectPickerWorkflowRequest] {
        guard !result.didConfirm else { return [.dismiss] }
        guard result == .missingDirectory else {
            return [.showFailure(ProjectPickerConfirmationFailurePresentation(result: result, path: path))]
        }
        return [.askRemoveStaleFrecency(path: path)]
    }

    func handleRemoveStaleFrecencyDecision(path: String, accepted: Bool) -> [ProjectPickerWorkflowRequest] {
        guard accepted else { return [] }
        frecencyStore.remove(path: path)
        refreshRecentRows()
        return []
    }

    private func openHighlighted() -> [ProjectPickerWorkflowRequest] {
        switch session.mode {
        case .recent:
            guard let index = session.recent.highlightedIndex else { return [] }
            return activateRecentRow(at: index)
        case .browse:
            guard let index = session.browse.highlightedIndex else { return [] }
            return activateBrowseRow(at: index)
        }
    }

    private func confirmTypedPath() -> [ProjectPickerWorkflowRequest] {
        let path = session.standardizedTypedPath
        guard session.typedPathState != .missing else {
            return [.askCreateDirectory(path: path)]
        }
        return [.confirmProjectPath(path: path, createIfMissing: false)]
    }

    private func reloadAfterBrowseInputChange(_ update: () -> Void) -> [ProjectPickerWorkflowRequest] {
        let previousInput = session.browse.input
        update()
        guard session.browse.input != previousInput else { return [] }
        scheduleDirectoryReload(pathState: session.pathState)
        return []
    }

    private func refreshRecentRows() {
        let filter = session.recent.filter
        let rows = frecencyStore.rankedRows(
            matching: filter,
            excluding: addedProjectPaths,
            limit: FrecencyStore.softCap
        )
        session.setRecentRows(rows)
    }

    private func scheduleDirectoryReload(pathState: ProjectPickerPathState) {
        cancelDirectoryReload()
        session.beginBrowseLoad()
        let loadID = UUID()
        directoryLoadID = loadID

        loadingMessageTask = Task { [weak self, loadingMessageDelay] in
            try? await Task.sleep(for: loadingMessageDelay)
            guard !Task.isCancelled else { return }
            self?.showLoadingMessage(loadID: loadID)
        }

        reloadTask = Task { [weak self, reloadDelay, directoryLoader] in
            try? await Task.sleep(for: reloadDelay)
            guard !Task.isCancelled else { return }
            let snapshot = await directoryLoader(pathState)
            guard !Task.isCancelled else { return }
            self?.applyDirectorySnapshot(snapshot, loadID: loadID)
        }
    }

    private func cancelDirectoryReload() {
        reloadTask?.cancel()
        loadingMessageTask?.cancel()
        reloadTask = nil
        loadingMessageTask = nil
        directoryLoadID = UUID()
        session.cancelBrowseLoad()
    }

    private func showLoadingMessage(loadID: UUID) {
        guard directoryLoadID == loadID, session.mode == .browse else { return }
        session.showBrowseLoadingMessage()
    }

    private func applyDirectorySnapshot(_ snapshot: ProjectPickerDirectorySnapshot, loadID: UUID) {
        guard directoryLoadID == loadID, session.mode == .browse else { return }
        loadingMessageTask?.cancel()
        loadingMessageTask = nil
        session.applyDirectorySnapshot(snapshot)
    }

    private static let liveDirectoryLoader: ProjectPickerDirectoryLoader = { pathState in
        await Task.detached(priority: .userInitiated) {
            ProjectPickerPathService(homeDirectory: pathState.homeDirectory).directorySnapshot(for: pathState)
        }.value
    }
}

enum ProjectPickerWorkflowRequest: Equatable {
    case askCreateDirectory(path: String)
    case confirmProjectPath(path: String, createIfMissing: Bool)
    case confirmFrecencyPath(path: String)
    case askRemoveStaleFrecency(path: String)
    case chooseFinder
    case openSettingsFocusedOnDefaultLocation
    case dismiss
    case showFailure(ProjectPickerConfirmationFailurePresentation)
}
