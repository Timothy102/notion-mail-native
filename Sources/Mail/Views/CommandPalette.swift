import MailCore
import SwiftUI

/// ⌘K palette (SPEC §4.6). Lists `app.commands.paletteCommands`; features never edit this file
/// to add actions, they register commands. Owner: palette/search feature.
struct CommandPalette: View {
    let mode: PaletteMode
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.scrim.onTapGesture { app.palette = nil }
                panel
                    .frame(width: min(Theme.Metrics.paletteWidth, geo.size.width - 80))
                    .padding(.top, geo.size.height * Theme.Metrics.paletteTopFraction)
            }
        }
        .onAppear { focused = true }
    }

    private var results: [Command] {
        let all = app.commands.paletteCommands
        guard !query.isEmpty else { return all }
        return all.filter { c in ([c.title] + c.keywords).contains { $0.localizedCaseInsensitiveContains(query) } }
    }

    private var panel: some View {
        let items = results
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Theme.iconSecondary).frame(width: 16)
                TextField(mode == .search ? "Search mail…" : "Search commands or mail…", text: $query)
                    .textFieldStyle(.plain)
                    .textStyle(.paletteInput)
                    .focused($focused)
                    .onSubmit { submit(items) }
                    .onKeyPress(.downArrow) { selection = min(selection + 1, max(items.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
            }
            .padding(.horizontal, 16)
            .frame(height: Theme.Metrics.paletteInputHeight)
            Hairline()
            if mode == .commands {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Command.Group.allCases, id: \.self) { group in
                            let rows = items.enumerated().filter { $0.element.group == group }
                            if !rows.isEmpty {
                                Text(group.rawValue)
                                    .textStyle(.smallSemibold)
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 8)
                                    .frame(height: 28, alignment: .bottom)
                                    .padding(.top, group == items.first?.group ? 4 : 12)
                                ForEach(rows, id: \.element.id) { index, command in
                                    row(command, selected: index == selection)
                                        .onHover { if $0 { selection = index } }
                                        .onTapGesture { run(command) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: Theme.Metrics.paletteMaxHeight - Theme.Metrics.paletteInputHeight - Theme.Metrics.paletteFooterHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
            Hairline()
            HStack(spacing: 16) {
                Text("⇅ Select")
                Text("↵ Open")
                Spacer()
            }
            .textStyle(.small)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 16)
            .frame(height: Theme.Metrics.paletteFooterHeight)
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusLarge, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radiusLarge, style: .continuous))
        .elevation(.l4, radius: Theme.Metrics.radiusLarge)
        .onChange(of: query) { selection = 0 }
    }

    private func row(_ command: Command, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: command.icon ?? "circle")
                .font(.system(size: 14))
                .foregroundStyle(Theme.iconSecondary)
                .frame(width: 20)
                .opacity(command.icon == nil ? 0 : 1)
            Text(command.title).textStyle(.body).lineLimit(1)
            Spacer(minLength: 8)
            if let shortcut = command.shortcuts.first {
                Text(shortcut.display).textStyle(.small).foregroundStyle(Theme.textTertiary).frame(minWidth: 78, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.Metrics.paletteRowHeight)
        .background(selected ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
        .contentShape(Rectangle())
    }

    private func submit(_ items: [Command]) {
        if mode == .search || items.isEmpty {
            let q = query.trimmingCharacters(in: .whitespaces)
            app.palette = nil
            if !q.isEmpty { app.search(q) }
        } else if items.indices.contains(selection) {
            run(items[selection])
        }
    }

    private func run(_ command: Command) {
        app.palette = nil
        command.perform()
    }
}
