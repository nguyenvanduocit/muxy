import AppKit
import SwiftUI

struct ProjectPickerOverlay: View {
    let projectPaths: [String]
    let onConfirm: (String, Bool) -> ProjectOpenConfirmationResult
    let onChooseFinder: () -> Void
    let onDismiss: () -> Void

    @Environment(\.openSettings) private var openSettings
    @State private var workflow: ProjectPickerWorkflow

    init(
        projectPaths: [String],
        frecencyStore: FrecencyStore,
        preferences: ProjectPickerPreferences = ProjectPickerPreferences(),
        onConfirm: @escaping (String, Bool) -> ProjectOpenConfirmationResult,
        onChooseFinder: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.projectPaths = projectPaths
        self.onConfirm = onConfirm
        self.onChooseFinder = onChooseFinder
        self.onDismiss = onDismiss
        _workflow = State(initialValue: ProjectPickerWorkflow(
            projectPaths: projectPaths,
            frecencyStore: frecencyStore,
            preferences: preferences
        ))
    }

    private var mode: ProjectPickerOverlayMode { workflow.session.mode }

    private var inputBinding: Binding<String> {
        Binding(
            get: { currentInputText },
            set: { value in
                switch mode {
                case .recent:
                    workflow.setRecentFilter(value)
                case .browse:
                    workflow.setBrowseInput(value)
                }
            }
        )
    }

    private var currentInputText: String {
        switch mode {
        case .recent:
            workflow.session.recent.filter
        case .browse:
            workflow.session.browse.input
        }
    }

    private var placeholder: String {
        switch mode {
        case .recent:
            "Filter recents…"
        case .browse:
            ""
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { handleCommand(.dismiss) }

            VStack(spacing: 0) {
                pathBar
                segmentedModeBar
                Divider().overlay(MuxyTheme.border)
                modeContent
                Divider().overlay(MuxyTheme.border)
                footer
            }
            .frame(width: UIMetrics.scaled(640), height: UIMetrics.scaled(460))
            .background(MuxyTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: UIMetrics.radiusXL))
            .overlay(RoundedRectangle(cornerRadius: UIMetrics.radiusXL).stroke(MuxyTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: UIMetrics.scaled(20), y: UIMetrics.scaled(8))
            .padding(.top, UIMetrics.scaled(60))
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { workflow.appear() }
        .onChange(of: projectPaths) { workflow.setProjectPaths($1) }
        .onDisappear { workflow.cancel() }
    }

    private var pathBar: some View {
        HStack(spacing: UIMetrics.spacing4) {
            Image(systemName: mode == .recent ? "magnifyingglass" : "folder")
                .font(.system(size: UIMetrics.fontBody, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgMuted)

            ZStack(alignment: .leading) {
                if currentInputText.isEmpty, !placeholder.isEmpty {
                    Text(placeholder)
                        .font(.system(size: UIMetrics.fontEmphasis, design: .monospaced))
                        .foregroundStyle(MuxyTheme.fgDim)
                        .allowsHitTesting(false)
                }
                if mode == .browse {
                    ghostTextPreview
                }
                ProjectPickerPathField(
                    text: inputBinding,
                    onCommand: handleCommand
                )
            }

            if mode == .browse {
                topRightActionMenu
            } else {
                recentSecondaryMenu
            }
        }
        .padding(.horizontal, UIMetrics.spacing6)
        .padding(.vertical, UIMetrics.spacing5)
    }

    private var segmentedModeBar: some View {
        HStack(spacing: UIMetrics.spacing2) {
            segmentButton(.recent, label: "Recent", keycap: "⌘1", command: .switchToRecent)
            segmentButton(.browse, label: "Browse", keycap: "⌘2", command: .switchToBrowse)
            Spacer()
        }
        .padding(.horizontal, UIMetrics.spacing6)
        .padding(.bottom, UIMetrics.spacing4)
    }

    private func segmentButton(
        _ target: ProjectPickerOverlayMode,
        label: String,
        keycap: String,
        command: ProjectPickerCommand
    ) -> some View {
        let isActive = mode == target
        return Button {
            handleCommand(command)
        } label: {
            HStack(spacing: UIMetrics.spacing2) {
                Text(label)
                    .font(.system(size: UIMetrics.fontFootnote, weight: .semibold))
                Text(keycap)
                    .font(.system(size: UIMetrics.fontCaption, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isActive ? MuxyTheme.fg.opacity(0.7) : MuxyTheme.fgDim)
            }
            .padding(.horizontal, UIMetrics.spacing4)
            .padding(.vertical, UIMetrics.spacing2)
            .background(isActive ? MuxyTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: UIMetrics.radiusMD))
            .overlay(
                RoundedRectangle(cornerRadius: UIMetrics.radiusMD)
                    .stroke(isActive ? MuxyTheme.accent.opacity(0.45) : MuxyTheme.border, lineWidth: 1)
            )
            .foregroundStyle(isActive ? MuxyTheme.fg : MuxyTheme.fgMuted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var secondaryMenuItems: some View {
        Button {
            chooseWithFinder()
        } label: {
            Label("Choose in Finder", systemImage: "folder")
        }
        Button {
            editDefaultLocation()
        } label: {
            if ProjectPickerDefaultLocation.state.isReady {
                Label("Edit Default Location", systemImage: "gearshape")
            } else {
                Label("Fix Default Location", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var topRightActionMenu: some View {
        HStack(spacing: 0) {
            Button(
                action: { handleCommand(.confirmTypedPath) },
                label: {
                    HStack(spacing: UIMetrics.spacing2) {
                        Image(systemName: "plus")
                            .font(.system(size: UIMetrics.fontFootnote, weight: .semibold))
                        Text(workflow.session.topRightActionTitle)
                            .font(.system(size: UIMetrics.fontFootnote, weight: .semibold))
                    }
                    .padding(.leading, UIMetrics.spacing3)
                    .padding(.trailing, UIMetrics.spacing4)
                    .padding(.vertical, UIMetrics.spacing2)
                    .contentShape(Rectangle())
                }
            )
            .buttonStyle(.plain)

            Rectangle()
                .fill(MuxyTheme.border)
                .frame(width: 1)

            Menu {
                secondaryMenuItems
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: UIMetrics.fontCaption, weight: .bold))
                    .padding(.horizontal, UIMetrics.spacing3)
                    .padding(.vertical, UIMetrics.spacing2)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
        .foregroundStyle(MuxyTheme.fg)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: UIMetrics.radiusMD))
        .overlay(RoundedRectangle(cornerRadius: UIMetrics.radiusMD).stroke(MuxyTheme.border, lineWidth: 1))
        .fixedSize()
    }

    private var recentSecondaryMenu: some View {
        Menu {
            secondaryMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: UIMetrics.fontCaption, weight: .bold))
                .padding(.horizontal, UIMetrics.spacing3)
                .padding(.vertical, UIMetrics.spacing2)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .foregroundStyle(MuxyTheme.fg)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: UIMetrics.radiusMD))
        .overlay(RoundedRectangle(cornerRadius: UIMetrics.radiusMD).stroke(MuxyTheme.border, lineWidth: 1))
        .fixedSize()
    }

    private var ghostTextPreview: some View {
        HStack(spacing: 0) {
            Text(workflow.session.browse.input)
                .foregroundStyle(.clear)
            Text(workflow.session.ghostText)
                .foregroundStyle(MuxyTheme.fgDim.opacity(0.65))
        }
        .font(.system(size: UIMetrics.fontEmphasis, design: .monospaced))
        .lineLimit(1)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .recent:
            recentContent
        case .browse:
            browseContent
        }
    }

    @ViewBuilder
    private var recentContent: some View {
        let rows = workflow.session.recent.rows
        if rows.isEmpty {
            recentEmptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                            ProjectPickerFrecencyRowView(
                                row: row,
                                isHighlighted: index == workflow.session.recent.highlightedIndex
                            )
                            .onTapGesture {
                                workflow.selectRecentRow(at: index)
                                execute(workflow.activateRecentRow(at: index))
                            }
                            .id(row)
                        }
                    }
                }
                .onChange(of: workflow.session.recent.highlightedIndex) { _, newIndex in
                    guard let newIndex, rows.indices.contains(newIndex) else { return }
                    proxy.scrollTo(rows[newIndex], anchor: nil)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var recentEmptyState: some View {
        VStack(spacing: UIMetrics.spacing4) {
            Text(recentEmptyTitle)
                .font(.system(size: UIMetrics.fontBody, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text(recentEmptyDescription)
                .font(.system(size: UIMetrics.fontFootnote))
                .foregroundStyle(MuxyTheme.fgDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: UIMetrics.scaled(420))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recentEmptyTitle: String {
        workflow.session.recent.filter.isEmpty
            ? "No recent projects yet"
            : "No matching recent project"
    }

    private var recentEmptyDescription: String {
        workflow.session.recent.filter.isEmpty
            ? "Once you open a few projects, they'll show up here. Press ⌘2 to browse."
            : "Press ⌘2 to browse folders."
    }

    @ViewBuilder
    private var browseContent: some View {
        let state = workflow.session.browse.directoryLoadState
        let hasItems = !workflow.session.browse.directoryItems.isEmpty
        if state.isLoading, !hasItems {
            browseLoadingContent
        } else if workflow.session.browseShowsUnavailableProjectState {
            browseUnavailableContent
        } else {
            browseRows
        }
    }

    private var browseLoadingContent: some View {
        VStack {
            Spacer()
            if workflow.session.browse.directoryLoadState.showsMessage {
                Text("Loading…")
                    .font(.system(size: UIMetrics.fontBody))
                    .foregroundStyle(MuxyTheme.fgMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var browseUnavailableContent: some View {
        VStack(spacing: 0) {
            if workflow.session.browseHasParentRow {
                browseParentDirectoryRow
            }
            browseUnavailableMessage
        }
    }

    @ViewBuilder
    private var browseParentDirectoryRow: some View {
        if let index = workflow.session.browse.directoryItems.firstIndex(where: \.isParent) {
            browseRow(at: index)
        }
    }

    private var browseRows: some View {
        let items = workflow.session.browse.directoryItems
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element) { index, _ in
                        browseRow(at: index)
                    }
                }
            }
            .onChange(of: workflow.session.browse.highlightedIndex) { _, newIndex in
                guard let newIndex, items.indices.contains(newIndex) else { return }
                proxy.scrollTo(items[newIndex], anchor: nil)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func browseRow(at index: Int) -> some View {
        let item = workflow.session.browse.directoryItems[index]
        return ProjectPickerDirectoryRowView(
            row: item,
            isHighlighted: index == workflow.session.browse.highlightedIndex
        )
        .onTapGesture {
            workflow.selectBrowseRow(at: index)
            execute(workflow.activateBrowseRow(at: index))
        }
        .id(item)
    }

    private var browseUnavailableMessage: some View {
        VStack(spacing: UIMetrics.spacing4) {
            Text("No project folders found")
                .font(.system(size: UIMetrics.fontBody, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text("Use the action above to open or create this project, go up, or choose with Finder.")
                .font(.system(size: UIMetrics.fontFootnote))
                .foregroundStyle(MuxyTheme.fgDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: UIMetrics.scaled(420))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: UIMetrics.scaled(18)) {
            ForEach(
                ProjectPickerFooterShortcut.ordered(mode: mode, actionTitle: workflow.session.topRightActionTitle),
                id: \.self
            ) { shortcut in
                ProjectPickerShortcutHint(shortcut: shortcut)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, UIMetrics.spacing5)
        .padding(.vertical, UIMetrics.spacing4)
    }

    private func chooseWithFinder() {
        execute(workflow.chooseWithFinder())
    }

    private func editDefaultLocation() {
        execute(workflow.editDefaultLocation())
    }

    private func handleCommand(_ command: ProjectPickerCommand) {
        execute(workflow.handle(command))
    }

    private func execute(_ requests: [ProjectPickerWorkflowRequest]) {
        for request in requests {
            executeSingle(request)
        }
    }

    private func executeSingle(_ request: ProjectPickerWorkflowRequest) {
        switch request {
        case let .askCreateDirectory(path):
            DispatchQueue.main.async {
                let accepted = confirmCreateDirectory(path: path)
                execute(workflow.handleCreateDirectoryDecision(path: path, accepted: accepted))
            }
        case let .confirmProjectPath(path, createIfMissing):
            let result = onConfirm(path, createIfMissing)
            execute(workflow.handleProjectPathConfirmationResult(result, path: path))
        case let .confirmFrecencyPath(path):
            let result = onConfirm(path, false)
            execute(workflow.handleFrecencyConfirmationResult(result, path: path))
        case let .askRemoveStaleFrecency(path):
            DispatchQueue.main.async {
                let accepted = confirmRemoveStaleFrecency(path: path)
                execute(workflow.handleRemoveStaleFrecencyDecision(path: path, accepted: accepted))
            }
        case .chooseFinder:
            DispatchQueue.main.async { onChooseFinder() }
        case .openSettingsFocusedOnDefaultLocation:
            DispatchQueue.main.async {
                openSettings()
                SettingsFocusCoordinator.shared.request(.projectPickerDefaultLocation)
            }
        case .dismiss:
            onDismiss()
        case let .showFailure(presentation):
            DispatchQueue.main.async {
                showConfirmationFailureAlert(presentation)
            }
        }
    }

    private func confirmCreateDirectory(path: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Create Project Folder?"
        alert.informativeText = "Muxy will create \"\(path)\" and add it as a project."
        alert.addButton(withTitle: "Create & Add")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmRemoveStaleFrecency(path: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Project Folder No Longer Exists"
        alert.informativeText = "Muxy couldn't find \"\(path)\". Remove it from the Recent list?"
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showConfirmationFailureAlert(_ presentation: ProjectPickerConfirmationFailurePresentation) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = presentation.title
        alert.informativeText = presentation.message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
