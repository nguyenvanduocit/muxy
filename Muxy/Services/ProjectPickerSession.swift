import Foundation

struct ProjectPickerSession {
    private(set) var mode: ProjectPickerOverlayMode
    private(set) var recent: RecentState
    private(set) var browse: BrowseState

    let homeDirectory: String
    let initialDisplayPath: String
    let pathService: ProjectPickerPathService
    var projectPaths: [String]

    var pathState: ProjectPickerPathState {
        pathService.state(for: browse.input)
    }

    var navigator: ProjectPickerNavigator {
        ProjectPickerNavigator(pathState: pathState)
    }

    var isAtDefaultInput: Bool {
        browse.input == initialDisplayPath
    }

    var standardizedTypedPath: String {
        pathState.standardizedConfirmPath
    }

    var typedPathState: ProjectPickerTypedPathState {
        pathService.typedPathState(path: standardizedTypedPath)
    }

    var isExistingProject: Bool {
        projectPaths.contains(standardizedTypedPath)
    }

    var actionTitle: String {
        if isExistingProject { return "Open" }
        return typedPathState == .missing ? "Create & Add" : "Add"
    }

    var topRightActionTitle: String {
        if isExistingProject { return "Open Project" }
        return typedPathState == .missing ? "Create & Add Project" : "Add Project"
    }

    var ghostText: String {
        guard mode == .browse,
              let highlighted = browse.highlightedItem,
              !highlighted.isParent
        else { return "" }
        return navigator.ghostText(highlightedRow: highlighted.name)
    }

    var browseProjectRows: [ProjectPickerDirectoryItem] {
        browse.directoryItems.filter { !$0.isParent }
    }

    var browseHasParentRow: Bool {
        browse.directoryItems.contains(where: \.isParent)
    }

    var browseShowsUnavailableProjectState: Bool {
        browse.directoryLoadState.readFailed || browseProjectRows.isEmpty
    }

    init(
        defaultDisplayPath: String,
        homeDirectory: String = NSHomeDirectory(),
        projectPaths: [String],
        mode: ProjectPickerOverlayMode = .browse,
        pathService: ProjectPickerPathService? = nil
    ) {
        self.mode = mode
        recent = RecentState()
        browse = BrowseState(input: defaultDisplayPath)
        initialDisplayPath = defaultDisplayPath
        self.homeDirectory = homeDirectory
        self.projectPaths = projectPaths
        self.pathService = pathService ?? ProjectPickerPathService(homeDirectory: homeDirectory)
    }

    mutating func setProjectPaths(_ projectPaths: [String]) {
        self.projectPaths = projectPaths
    }

    mutating func setMode(_ newMode: ProjectPickerOverlayMode) {
        mode = newMode
    }

    mutating func setRecentFilter(_ filter: String) {
        recent.filter = filter
        recent.highlightedIndex = nil
    }

    mutating func setRecentRows(_ rows: [FrecencyRow]) {
        recent.rows = rows
        recent.highlightedIndex = recentClampedHighlight()
    }

    mutating func selectRecentRow(at index: Int) {
        guard recent.rows.indices.contains(index) else { return }
        recent.highlightedIndex = index
    }

    mutating func setBrowseInput(_ input: String) {
        browse.input = input
        browse.highlightedIndex = nil
    }

    mutating func showBrowseLoadingMessage() {
        guard browse.directoryLoadState.isLoading else { return }
        browse.directoryLoadState = .loading(showsMessage: true)
    }

    mutating func beginBrowseLoad() {
        browse.directoryLoadState = .loading(showsMessage: false)
    }

    mutating func cancelBrowseLoad() {
        browse.directoryLoadState = .idle
    }

    mutating func selectBrowseRow(at index: Int) {
        guard browse.directoryItems.indices.contains(index) else { return }
        browse.highlightedIndex = index
    }

    mutating func applyDirectorySnapshot(_ snapshot: ProjectPickerDirectorySnapshot) {
        browse.directoryLoadState = snapshot.readFailed ? .failed : .loaded
        browse.directoryItems = snapshot.rows
        browse.highlightedIndex = browseInitialHighlight()
    }

    mutating func handle(_ command: ProjectPickerCommand) {
        switch mode {
        case .recent:
            handleRecent(command)
        case .browse:
            handleBrowse(command)
        }
    }

    func resolveRecentActivation(at index: Int) -> ProjectPickerSessionActivation? {
        guard recent.rows.indices.contains(index) else { return nil }
        return .confirmPath(recent.rows[index].path)
    }

    mutating func activateBrowseRow(at index: Int) -> ProjectPickerSessionActivation? {
        guard browse.directoryItems.indices.contains(index) else { return nil }
        let row = browse.directoryItems[index]
        guard !browse.directoryLoadState.isLoading || row.isParent else { return nil }
        descend(row)
        return .descended
    }

    private mutating func handleRecent(_ command: ProjectPickerCommand) {
        switch command {
        case .moveHighlightUp:
            moveRecentHighlight(-1)
        case .moveHighlightDown:
            moveRecentHighlight(1)
        case .openHighlighted,
             .confirmTypedPath,
             .completeHighlighted,
             .switchToRecent,
             .switchToBrowse,
             .goBack,
             .dismiss:
            return
        }
    }

    private mutating func handleBrowse(_ command: ProjectPickerCommand) {
        switch command {
        case .moveHighlightUp:
            moveBrowseHighlight(-1)
        case .moveHighlightDown:
            moveBrowseHighlight(1)
        case .openHighlighted,
             .confirmTypedPath,
             .switchToRecent,
             .switchToBrowse,
             .dismiss:
            return
        case .goBack:
            goUp()
        case .completeHighlighted:
            guard let highlighted = browse.highlightedItem, !highlighted.isParent else { return }
            setBrowseInput(navigator.completedPath(highlightedRow: highlighted.name))
        }
    }

    private mutating func moveRecentHighlight(_ delta: Int) {
        let rows = recent.rows
        guard !rows.isEmpty else { return }
        guard let current = recent.highlightedIndex else {
            recent.highlightedIndex = delta > 0 ? 0 : rows.count - 1
            return
        }
        recent.highlightedIndex = max(0, min(rows.count - 1, current + delta))
    }

    private mutating func moveBrowseHighlight(_ delta: Int) {
        let items = browse.directoryItems
        guard !items.isEmpty else { return }
        guard let current = browse.highlightedIndex else {
            browse.highlightedIndex = delta > 0 ? 0 : items.count - 1
            return
        }
        browse.highlightedIndex = max(0, min(items.count - 1, current + delta))
    }

    private mutating func descend(_ row: ProjectPickerDirectoryItem) {
        if row.isParent {
            goUp()
            return
        }
        setBrowseInput(navigator.completedPath(highlightedRow: row.name))
    }

    private mutating func goUp() {
        let parentPath = navigator.parentDisplayPath
        guard parentPath != browse.input else { return }
        setBrowseInput(parentPath)
    }

    private func browseInitialHighlight() -> Int? {
        let items = browse.directoryItems
        guard !items.isEmpty else { return nil }
        guard items.first?.isParent == true, items.count > 1 else { return 0 }
        return 1
    }

    private func recentClampedHighlight() -> Int? {
        let rows = recent.rows
        guard !rows.isEmpty else { return nil }
        guard let highlighted = recent.highlightedIndex else { return 0 }
        return min(highlighted, rows.count - 1)
    }
}

struct RecentState {
    var filter: String = ""
    var rows: [FrecencyRow] = []
    var highlightedIndex: Int?

    var highlightedItem: FrecencyRow? {
        guard let highlightedIndex, rows.indices.contains(highlightedIndex) else { return nil }
        return rows[highlightedIndex]
    }
}

struct BrowseState {
    var input: String
    var directoryItems: [ProjectPickerDirectoryItem] = []
    var directoryLoadState: ProjectPickerDirectoryLoadState = .idle
    var highlightedIndex: Int?

    var highlightedItem: ProjectPickerDirectoryItem? {
        guard let highlightedIndex, directoryItems.indices.contains(highlightedIndex) else { return nil }
        return directoryItems[highlightedIndex]
    }
}

struct ProjectPickerConfirmationFailurePresentation: Equatable {
    let title: String
    let message: String

    init(result: ProjectOpenConfirmationResult, path: String) {
        switch result {
        case .notDirectory:
            title = "Path Is Not a Folder"
            message = "Muxy can only add folders as projects. Choose a folder or type a new folder path."
        case .missingDirectory:
            title = "Could Not Add Project"
            message = "Muxy couldn't find \"\(path)\". Check the path and try again."
        case .createFailed:
            title = "Could Not Create Project Folder"
            message = "Muxy couldn't create and add \"\(path)\". Check that you have permission to use this location."
        default:
            title = "Could Not Add Project"
            message = "Muxy couldn't add \"\(path)\". Check that the folder exists and you have permission to use it."
        }
    }
}

enum ProjectPickerDirectoryLoadState: Equatable {
    case idle
    case loading(showsMessage: Bool)
    case loaded
    case failed

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var showsMessage: Bool {
        if case let .loading(showsMessage) = self { return showsMessage }
        return false
    }

    var readFailed: Bool {
        self == .failed
    }

    var needsLoad: Bool {
        switch self {
        case .loaded:
            false
        case .idle,
             .loading,
             .failed:
            true
        }
    }
}
