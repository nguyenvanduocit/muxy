import Foundation
import Testing

@testable import Muxy

@Suite("ProjectPickerSession")
struct ProjectPickerSessionTests {
    @Test("default mode is browse and browse input starts at the default display path")
    func defaultsInitializeBrowseMode() {
        let session = ProjectPickerSession(defaultDisplayPath: "~/", homeDirectory: "/Users/alice", projectPaths: [])

        #expect(session.mode == .browse)
        #expect(session.browse.input == "~/")
        #expect(session.recent.filter.isEmpty)
        #expect(session.recent.rows.isEmpty)
    }

    @Test("browse input change clears highlight and keeps items for stale-while-revalidate")
    func browseInputChangeKeepsItems() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/", homeDirectory: "/Users/alice", projectPaths: [])
        session.applyDirectorySnapshot(ProjectPickerDirectorySnapshot(rows: ["a", "b"], readFailed: false))
        session.selectBrowseRow(at: 1)
        #expect(session.browse.directoryItems.count == 2)

        session.setBrowseInput("~/Projects/mu")

        #expect(session.browse.input == "~/Projects/mu")
        #expect(session.browse.directoryItems.count == 2)
        #expect(session.browse.highlightedIndex == nil)
    }

    @Test("activating a stale browse row while loading is a no-op")
    func staleBrowseRowClickDuringLoadingIsNoOp() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/Projects/", homeDirectory: "/Users/alice", projectPaths: [])
        session.applyDirectorySnapshot(ProjectPickerDirectorySnapshot(rows: ["muxy", "api"], readFailed: false))
        session.setBrowseInput("~/Documents/")
        session.beginBrowseLoad()
        #expect(session.browse.directoryLoadState.isLoading)
        #expect(session.browse.directoryItems.map(\.name) == ["muxy", "api"])

        let activation = session.activateBrowseRow(at: 0)

        #expect(activation == nil)
        #expect(session.browse.input == "~/Documents/")
    }

    @Test("activating the parent row is allowed even while loading")
    func parentRowActivationAllowedWhileLoading() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/Projects/sub/", homeDirectory: "/Users/alice", projectPaths: [])
        session.applyDirectorySnapshot(ProjectPickerDirectorySnapshot(rows: ["..", "muxy"], readFailed: false))
        session.beginBrowseLoad()
        #expect(session.browse.directoryLoadState.isLoading)

        let activation = session.activateBrowseRow(at: 0)

        #expect(activation == .descended)
        #expect(session.browse.input == "~/Projects/")
    }

    @Test("beginBrowseLoad transitions state to loading")
    func beginBrowseLoadTransitionsToLoading() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/", homeDirectory: "/Users/alice", projectPaths: [])
        #expect(session.browse.directoryLoadState == .idle)

        session.beginBrowseLoad()

        #expect(session.browse.directoryLoadState == .loading(showsMessage: false))
    }

    @Test("snapshot application chooses first real row after parent row")
    func snapshotApplicationChoosesInitialHighlight() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/", homeDirectory: "/Users/alice", projectPaths: [])

        session.applyDirectorySnapshot(ProjectPickerDirectorySnapshot(rows: ["..", "Code", "Documents"], readFailed: false))

        #expect(session.browse.directoryLoadState == .loaded)
        #expect(session.browse.highlightedIndex == 1)
        #expect(session.browse.highlightedItem?.name == "Code")
    }

    @Test("browse navigation, completion, and parent commands update state")
    func browseCommandStateTransitions() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/Projects/mu", homeDirectory: "/Users/alice", projectPaths: [])
        session.applyDirectorySnapshot(ProjectPickerDirectorySnapshot(rows: ["muxy", "sample"], readFailed: false))

        session.handle(.moveHighlightDown)
        #expect(session.browse.highlightedIndex == 1)

        session.handle(.completeHighlighted)
        #expect(session.browse.input == "~/Projects/sample/")

        session.handle(.goBack)
        #expect(session.browse.input == "~/Projects/")
    }

    @Test("activating a browse directory descends and parent row goes up")
    func browseActivationDescendsAndParentGoesUp() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/Projects/", homeDirectory: "/Users/alice", projectPaths: [])
        session.applyDirectorySnapshot(ProjectPickerDirectorySnapshot(rows: ["..", "muxy"], readFailed: false))

        let descended = session.browse.highlightedIndex.flatMap { session.activateBrowseRow(at: $0) }

        #expect(descended == .descended)
        #expect(session.browse.input == "~/Projects/muxy/")

        session.applyDirectorySnapshot(ProjectPickerDirectorySnapshot(rows: [".."], readFailed: false))
        session.selectBrowseRow(at: 0)
        let parentActivation = session.browse.highlightedIndex.flatMap { session.activateBrowseRow(at: $0) }

        #expect(parentActivation == .descended)
        #expect(session.browse.input == "~/Projects/")
    }

    @Test("typed path state drives action titles")
    func typedPathStateDrivesActionTitles() {
        let pathService = ProjectPickerPathService(
            fileSystem: ProjectPickerFileSystemStub(directoryStates: [
                "/tmp/existing": .directory,
                "/tmp/existing/missing": .missing,
            ])
        )

        let existingSession = ProjectPickerSession(
            defaultDisplayPath: "/tmp/existing",
            projectPaths: [],
            pathService: pathService
        )
        #expect(existingSession.typedPathState == .directory)
        #expect(existingSession.actionTitle == "Add")
        #expect(existingSession.topRightActionTitle == "Add Project")

        let missingSession = ProjectPickerSession(
            defaultDisplayPath: "/tmp/existing/missing",
            projectPaths: [],
            pathService: pathService
        )
        #expect(missingSession.typedPathState == .missing)
        #expect(missingSession.actionTitle == "Create & Add")
        #expect(missingSession.topRightActionTitle == "Create & Add Project")
    }

    @Test("existing project updates action titles")
    func existingProjectUpdatesActionTitles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-project-picker-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = ProjectPickerSession(defaultDisplayPath: root.path, projectPaths: [root.standardizedFileURL.resolvingSymlinksInPath().path])

        #expect(session.actionTitle == "Open")
        #expect(session.topRightActionTitle == "Open Project")
    }

    @Test("resolving a recent row yields a confirm-path activation")
    func resolveRecentActivationYieldsConfirmPath() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/", homeDirectory: "/Users/alice", projectPaths: [], mode: .recent)
        session.setRecentRows([
            FrecencyRow(path: "/Users/alice/work/api", displayName: "api", displayDirectory: "~/work/"),
        ])

        let activation = session.resolveRecentActivation(at: 0)

        #expect(activation == .confirmPath("/Users/alice/work/api"))
    }

    @Test("isAtDefaultInput tracks the captured initial display path")
    func isAtDefaultInputTracksInitialPath() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/", homeDirectory: "/Users/alice", projectPaths: [])

        #expect(session.isAtDefaultInput)

        session.setBrowseInput("~/Projects/")
        #expect(!session.isAtDefaultInput)

        session.setBrowseInput("~/")
        #expect(session.isAtDefaultInput)
    }

    @Test("recent navigation moves highlight independently of browse state")
    func recentNavigationIsIndependent() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/", homeDirectory: "/Users/alice", projectPaths: [], mode: .recent)
        session.setRecentRows([
            FrecencyRow(path: "/Users/alice/work/api", displayName: "api", displayDirectory: "~/work/"),
            FrecencyRow(path: "/Users/alice/work/web", displayName: "web", displayDirectory: "~/work/"),
        ])
        #expect(session.recent.highlightedIndex == 0)

        session.handle(.moveHighlightDown)
        #expect(session.recent.highlightedIndex == 1)
        #expect(session.browse.highlightedIndex == nil)
    }

    @Test("recent ignores commands that only make sense for browse")
    func recentIgnoresBrowseOnlyCommands() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/", homeDirectory: "/Users/alice", projectPaths: [], mode: .recent)
        session.setRecentRows([
            FrecencyRow(path: "/Users/alice/work/api", displayName: "api", displayDirectory: "~/work/"),
        ])
        let beforeFilter = session.recent.filter
        let beforeBrowseInput = session.browse.input

        session.handle(.completeHighlighted)
        session.handle(.goBack)

        #expect(session.recent.filter == beforeFilter)
        #expect(session.browse.input == beforeBrowseInput)
    }

    @Test("ghost text is empty in recent mode")
    func ghostTextEmptyInRecentMode() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/", homeDirectory: "/Users/alice", projectPaths: [], mode: .recent)
        session.setRecentRows([
            FrecencyRow(path: "/Users/alice/work/api", displayName: "api", displayDirectory: "~/work/"),
        ])

        #expect(session.ghostText == "")
    }

    @Test("changing recent filter resets the highlight to the top row")
    func recentFilterChangeResetsHighlight() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/", homeDirectory: "/Users/alice", projectPaths: [], mode: .recent)
        session.setRecentRows([
            FrecencyRow(path: "/Users/alice/work/api", displayName: "api", displayDirectory: "~/work/"),
            FrecencyRow(path: "/Users/alice/work/web", displayName: "web", displayDirectory: "~/work/"),
        ])
        session.selectRecentRow(at: 1)
        #expect(session.recent.highlightedIndex == 1)

        session.setRecentFilter("a")
        session.setRecentRows([
            FrecencyRow(path: "/Users/alice/work/api", displayName: "api", displayDirectory: "~/work/"),
        ])

        #expect(session.recent.highlightedIndex == 0)
    }

    @Test("switching mode preserves the other mode's state")
    func switchingModePreservesOtherStates() {
        var session = ProjectPickerSession(defaultDisplayPath: "~/", homeDirectory: "/Users/alice", projectPaths: [])
        session.setBrowseInput("~/Projects/")
        session.applyDirectorySnapshot(ProjectPickerDirectorySnapshot(rows: ["muxy"], readFailed: false))
        session.selectBrowseRow(at: 0)

        session.setMode(.recent)
        session.setRecentFilter("api")
        session.setRecentRows([
            FrecencyRow(path: "/Users/alice/work/api", displayName: "api", displayDirectory: "~/work/"),
        ])
        session.selectRecentRow(at: 0)

        session.setMode(.browse)

        #expect(session.mode == .browse)
        #expect(session.browse.input == "~/Projects/")
        #expect(session.browse.directoryItems.map(\.name) == ["muxy"])
        #expect(session.browse.highlightedIndex == 0)

        session.setMode(.recent)

        #expect(session.recent.filter == "api")
        #expect(session.recent.rows.map(\.displayName) == ["api"])
        #expect(session.recent.highlightedIndex == 0)
    }
}

private struct ProjectPickerFileSystemStub: ProjectPickerFileSystem {
    let directoryStates: [String: ProjectPickerFileSystemDirectoryState]

    func directoryState(atPath path: String) -> ProjectPickerFileSystemDirectoryState {
        directoryStates[path] ?? .missing
    }

    func isReadableFile(atPath path: String) -> Bool {
        directoryStates[path] == .directory
    }

    func contentsOfDirectory(atPath path: String) throws -> [ProjectPickerFileSystemDirectoryEntry] {
        []
    }
}
