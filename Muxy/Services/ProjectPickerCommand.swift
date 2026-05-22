import Foundation

enum ProjectPickerCommand: Hashable {
    case moveHighlightUp
    case moveHighlightDown
    case openHighlighted
    case confirmTypedPath
    case goBack
    case dismiss
    case completeHighlighted
    case switchToRecent
    case switchToBrowse

    static var handledIntents: Set<ProjectPickerCommand> {
        Set(allCases)
    }

    static func footerShortcuts(mode: ProjectPickerOverlayMode, actionTitle: String) -> [ProjectPickerFooterShortcut] {
        switch mode {
        case .recent:
            [
                ProjectPickerFooterShortcut(intents: [.moveHighlightUp, .moveHighlightDown], keycap: .navigate, label: "Navigate"),
                ProjectPickerFooterShortcut(intents: [.openHighlighted], keycap: .returnKey, label: "Open"),
                ProjectPickerFooterShortcut(intents: [.switchToBrowse], keycap: .commandTwo, label: "Browse"),
                ProjectPickerFooterShortcut(intents: [.dismiss], keycap: .escape, label: "Close"),
            ]
        case .browse:
            [
                ProjectPickerFooterShortcut(intents: [.moveHighlightUp, .moveHighlightDown], keycap: .navigate, label: "Navigate"),
                ProjectPickerFooterShortcut(intents: [.completeHighlighted], keycap: .tab, label: "Autocomplete"),
                ProjectPickerFooterShortcut(intents: [.openHighlighted], keycap: .returnKey, label: "Open"),
                ProjectPickerFooterShortcut(intents: [.confirmTypedPath], keycap: .commandReturn, label: actionTitle),
                ProjectPickerFooterShortcut(intents: [.goBack], keycap: .optionDelete, label: "Go back"),
                ProjectPickerFooterShortcut(intents: [.switchToRecent], keycap: .commandOne, label: "Recent"),
                ProjectPickerFooterShortcut(intents: [.dismiss], keycap: .escape, label: "Close"),
            ]
        }
    }
}

extension ProjectPickerCommand: CaseIterable {}

struct ProjectPickerFooterShortcut: Hashable {
    let intents: [ProjectPickerCommand]
    let keycap: ProjectPickerShortcutKeycap
    let label: String

    static func ordered(mode: ProjectPickerOverlayMode, actionTitle: String) -> [ProjectPickerFooterShortcut] {
        ProjectPickerCommand.footerShortcuts(mode: mode, actionTitle: actionTitle)
    }
}

struct ProjectPickerShortcutKeycap: Hashable {
    let parts: [ProjectPickerShortcutKeycapPart]

    static let navigate = ProjectPickerShortcutKeycap(parts: [.symbol("arrow.up"), .symbol("arrow.down")])
    static let tab = ProjectPickerShortcutKeycap(parts: [.text("Tab")])
    static let returnKey = ProjectPickerShortcutKeycap(parts: [.symbol("return")])
    static let commandReturn = ProjectPickerShortcutKeycap(parts: [.symbol("command"), .symbol("return")])
    static let escape = ProjectPickerShortcutKeycap(parts: [.text("Esc")])
    static let optionDelete = ProjectPickerShortcutKeycap(parts: [.symbol("option"), .symbol("delete.left")])
    static let commandOne = ProjectPickerShortcutKeycap(parts: [.symbol("command"), .text("1")])
    static let commandTwo = ProjectPickerShortcutKeycap(parts: [.symbol("command"), .text("2")])
}

enum ProjectPickerShortcutKeycapPart: Hashable {
    case symbol(String)
    case text(String)
}
