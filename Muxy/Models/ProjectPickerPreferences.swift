import Foundation

enum ProjectPickerPresentationMode: String, CaseIterable, Identifiable {
    case custom
    case finder

    var id: String { rawValue }

    var label: String {
        switch self {
        case .custom:
            "Custom"
        case .finder:
            "Finder"
        }
    }
}

final class ProjectPickerPreferences {
    static let storageKey = "muxy.projectPicker.mode"
    static let overlayModeStorageKey = "muxy.projectPicker.overlayMode"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mode: ProjectPickerPresentationMode {
        get {
            guard let rawValue = defaults.string(forKey: Self.storageKey),
                  let mode = ProjectPickerPresentationMode(rawValue: rawValue)
            else { return .custom }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.storageKey)
        }
    }

    var overlayMode: ProjectPickerOverlayMode {
        get {
            guard let rawValue = defaults.string(forKey: Self.overlayModeStorageKey),
                  let mode = ProjectPickerOverlayMode(rawValue: rawValue)
            else { return .browse }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.overlayModeStorageKey)
        }
    }
}
