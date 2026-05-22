import SwiftUI

struct ProjectPickerDirectoryRowView: View {
    let row: ProjectPickerDirectoryItem
    let isHighlighted: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: UIMetrics.spacing3) {
            icon
                .frame(width: UIMetrics.scaled(16), height: UIMetrics.scaled(16))
            Text(row.name)
                .font(.system(size: UIMetrics.fontBody, design: .monospaced))
            Spacer()
        }
        .padding(.horizontal, UIMetrics.spacing5)
        .padding(.vertical, UIMetrics.spacing3)
        .background(isHighlighted ? MuxyTheme.surface : hovered ? MuxyTheme.hover : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var icon: some View {
        if row.isParent {
            Image(systemName: "arrow.turn.up.left")
                .foregroundStyle(MuxyTheme.fgMuted)
        } else if row.isDirectorySymlink {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "folder")
                    .foregroundStyle(MuxyTheme.fgMuted)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: UIMetrics.scaled(7), weight: .bold))
                    .foregroundStyle(MuxyTheme.fg)
                    .padding(1)
                    .background(MuxyTheme.surface, in: Circle())
                    .offset(x: UIMetrics.scaled(3), y: UIMetrics.scaled(2))
            }
        } else {
            Image(systemName: "folder")
                .foregroundStyle(MuxyTheme.fgMuted)
        }
    }
}

struct ProjectPickerFrecencyRowView: View {
    let row: FrecencyRow
    let isHighlighted: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: UIMetrics.spacing3) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(MuxyTheme.fgMuted)
                .frame(width: UIMetrics.scaled(16), height: UIMetrics.scaled(16))
            Text(row.displayName)
                .font(.system(size: UIMetrics.fontBody, design: .monospaced))
            Text(row.displayDirectory)
                .font(.system(size: UIMetrics.fontFootnote, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgDim)
            Spacer()
        }
        .padding(.horizontal, UIMetrics.spacing5)
        .padding(.vertical, UIMetrics.spacing3)
        .background(isHighlighted ? MuxyTheme.surface : hovered ? MuxyTheme.hover : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}
