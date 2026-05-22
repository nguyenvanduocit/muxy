import Testing

@testable import Muxy

@Suite("ProjectPickerFooterShortcut")
struct ProjectPickerFooterShortcutTests {
    @Test("browse footer lists path-typing shortcuts and a switch to recent")
    func browseFooterShortcuts() {
        let shortcuts = ProjectPickerFooterShortcut.ordered(mode: .browse, actionTitle: "Add Project")

        #expect(shortcuts.map(\.label) == ["Navigate", "Autocomplete", "Open", "Add Project", "Go back", "Recent", "Close"])
        #expect(shortcuts.map(\.intents) == [
            [.moveHighlightUp, .moveHighlightDown],
            [.completeHighlighted],
            [.openHighlighted],
            [.confirmTypedPath],
            [.goBack],
            [.switchToRecent],
            [.dismiss],
        ])
        #expect(shortcuts.flatMap(\.intents).allSatisfy(ProjectPickerCommand.handledIntents.contains))
        #expect(shortcuts[1].keycap == .tab)
        #expect(shortcuts[4].keycap == .optionDelete)
        #expect(shortcuts[5].keycap == .commandOne)
        #expect(shortcuts[6].keycap == .escape)
    }

    @Test("recent footer omits browse-only shortcuts and offers switch to browse")
    func recentFooterShortcuts() {
        let shortcuts = ProjectPickerFooterShortcut.ordered(mode: .recent, actionTitle: "Add Project")

        #expect(shortcuts.map(\.label) == ["Navigate", "Open", "Browse", "Close"])
        #expect(shortcuts.map(\.intents) == [
            [.moveHighlightUp, .moveHighlightDown],
            [.openHighlighted],
            [.switchToBrowse],
            [.dismiss],
        ])
        #expect(shortcuts[2].keycap == .commandTwo)
        #expect(shortcuts[3].keycap == .escape)
    }

    @Test("browse typed path action title changes label without changing command identity")
    func typedPathActionTitleOnlyChangesLabel() {
        let addShortcuts = ProjectPickerFooterShortcut.ordered(mode: .browse, actionTitle: "Add Project")
        let createShortcuts = ProjectPickerFooterShortcut.ordered(mode: .browse, actionTitle: "Create & Add Project")

        #expect(addShortcuts.map(\.intents) == createShortcuts.map(\.intents))
        #expect(addShortcuts[3].label == "Add Project")
        #expect(createShortcuts[3].label == "Create & Add Project")
        #expect(addShortcuts[3].intents == [.confirmTypedPath])
    }
}
