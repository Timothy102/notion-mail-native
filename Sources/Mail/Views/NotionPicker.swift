import MailCore
import SwiftUI

/// Palette-style picker behind "Save to Notion" (choose a database, create a page for the
/// thread) and "Link to Notion page" (search pages, store the thread → page link).
struct NotionPicker: View {
    let request: NotionPickerRequest
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var results: [NotionObject] = []
    @State private var phase = Phase.searching
    @State private var selection = 0
    @FocusState private var focused: Bool

    enum Phase: Equatable { case searching, ready, saving(String), failed(String) }

    private var client: NotionClient { NotionClient(demo: app.isDemo) }
    private var isSave: Bool { request.kind == .database }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.scrim.onTapGesture { app.notionPicker = nil }
                panel
                    .frame(width: min(Theme.Metrics.paletteWidth, geo.size.width - 80))
                    .padding(.top, geo.size.height * Theme.Metrics.paletteTopFraction)
            }
        }
        .onAppear { focused = true }
        .task(id: query) {
            guard client.isConnected else { return }
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            if Task.isCancelled { return }
            if results.isEmpty { phase = .searching }
            do {
                let found = try await client.search(query, kind: request.kind)
                if Task.isCancelled { return }
                results = found
                selection = 0
                phase = .ready
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Theme.iconSecondary).frame(width: 16)
                TextField(isSave ? "Save to a Notion database…" : "Link to a Notion page…", text: $query)
                    .textFieldStyle(.plain)
                    .textStyle(.paletteInput)
                    .focused($focused)
                    .disabled(!client.isConnected)
                    .onSubmit { choose(selection) }
                    .onKeyPress(.downArrow) { selection = min(selection + 1, max(results.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
                threadChip
            }
            .padding(.horizontal, 16)
            .frame(height: Theme.Metrics.paletteInputHeight)
            Hairline()
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Hairline()
            footer
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusLarge, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radiusLarge, style: .continuous))
        .elevation(.l4, radius: Theme.Metrics.radiusLarge)
    }

    /// The thread being saved or linked, so it is clear what the action applies to.
    private var threadChip: some View {
        let subject = (try? app.store.db.read { try MailThread.fetchOne($0, key: request.threadId)?.subject }) ?? nil
        return HStack(spacing: 4) {
            Image(systemName: "envelope").font(.system(size: 11)).foregroundStyle(Theme.iconSecondary)
            Text(subject.flatMap { $0.isEmpty ? nil : $0 } ?? "(no subject)").textStyle(.small).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .frame(maxWidth: 220, alignment: .leading)
        .background(Theme.wash, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusSmall, style: .continuous))
        .fixedSize()
        .frame(maxWidth: 220, alignment: .trailing)
    }

    @ViewBuilder
    private var content: some View {
        if !client.isConnected {
            message(title: "Connect Notion", text: "Add your Notion integration token in Settings to save and link threads.") {
                Button("Open Integrations") { app.notionPicker = nil; app.settings = .integrations }
                    .buttonStyle(.primary)
            }
        } else {
            switch phase {
            case .searching:
                status { DotsLoader(); Text("Searching Notion…") }
            case .saving(let title):
                status { DotsLoader(); Text("Saving to \(title)…") }
            case .failed(let error):
                message(title: "Couldn't reach Notion", text: error) {
                    Button("Retry") { phase = .searching; retry() }
                        .buttonStyle(.outline)
                }
            case .ready where results.isEmpty:
                message(title: query.isEmpty ? (isSave ? "No databases yet" : "No pages yet") : "No results",
                        text: "Share a \(isSave ? "database" : "page") with your integration from its ••• menu → Connections.") { EmptyView() }
            case .ready:
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(isSave ? "Databases" : "Pages")
                                .textStyle(.smallSemibold)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 8)
                                .frame(height: 28, alignment: .bottom)
                                .padding(.top, 4)
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, object in
                                row(object, selected: index == selection)
                                    .id(index)
                                    .onHover { if $0 { selection = index } }
                                    .onTapGesture { choose(index) }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: Theme.Metrics.paletteMaxHeight - Theme.Metrics.paletteInputHeight - Theme.Metrics.paletteFooterHeight)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: selection) { proxy.scrollTo(selection) }
                }
            }
        }
    }

    private func row(_ object: NotionObject, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if let icon = object.icon {
                    Text(icon).font(.system(size: 14))
                } else {
                    Image(systemName: object.kind == .database ? "tablecells" : "doc.text")
                        .font(.system(size: 14)).foregroundStyle(Theme.iconSecondary)
                }
            }
            .frame(width: 20)
            Text(object.title).textStyle(.body).lineLimit(1)
            Spacer(minLength: 8)
            if let edited = object.lastEdited {
                Text("Edited " + MailDate.list(edited)).textStyle(.small).foregroundStyle(Theme.textTertiary).lineLimit(1).fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.Metrics.paletteRowHeight)
        .background(selected ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
        .contentShape(Rectangle())
    }

    private func status(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 8) { content() }
            .textStyle(.body)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 16)
            .frame(height: 56)
    }

    private func message(title: String, text: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(spacing: 4) {
            Text(title).textStyle(.bodyMedium)
            Text(text)
                .textStyle(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
            action().padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if client.isConnected {
                Text("⇅ Select")
                Text(isSave ? "↵ Save" : "↵ Link")
            }
            Spacer()
            Text("Esc Close")
        }
        .textStyle(.small)
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 16)
        .frame(height: Theme.Metrics.paletteFooterHeight)
    }

    private func retry() {
        Task {
            do {
                results = try await client.search(query, kind: request.kind)
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func choose(_ index: Int) {
        guard phase == .ready, results.indices.contains(index) else { return }
        let object = results[index]
        let threadId = request.threadId
        if isSave {
            phase = .saving(object.title)
            Task {
                do {
                    guard let detail = try await app.store.db.read({ try Store.threadDetail($0, id: threadId) }) else { return }
                    let link = try await client.savePage(detail, to: object)
                    try app.store.save(notionLink: link)
                    app.notionPicker = nil
                    app.show(Toast("Saved to \(object.title)"))
                } catch {
                    phase = .failed(error.localizedDescription)
                }
            }
        } else {
            do {
                try app.store.save(notionLink: NotionLink(threadId: threadId, pageId: object.id, title: object.title, url: object.url))
                app.notionPicker = nil
                app.show(Toast("Linked to \(object.title)"))
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
