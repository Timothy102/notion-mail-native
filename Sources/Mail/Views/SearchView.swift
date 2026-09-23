import MailCore
import SwiftUI

/// Search results in the list pane (SPEC §4.7): the local FTS index first, Gmail's own search
/// when the query uses operators only Gmail knows or nothing matched locally.
struct SearchView: View {
    let query: String
    @Environment(AppState.self) private var app
    @State private var local = Live<[SearchHit]>([])
    @State private var remote = Live<[MailThread]>([])
    @State private var gmail = GmailState.idle
    @State private var labels = Live<[MailLabel]>([])

    private enum GmailState: Equatable { case idle, searching, done, failed }

    private var parsed: SearchQuery { SearchQuery(query) }

    private var hits: [SearchHit] {
        gmail == .done && (parsed.needsGmail || local.value.isEmpty) ? remote.value.map { SearchHit(thread: $0) } : local.value
    }

    var body: some View {
        let hits = hits
        GeometryReader { geo in
            let layout = RowLayout(paneWidth: geo.size.width, windowWidth: geo.size.width + (app.isSidebarVisible ? Theme.Metrics.sidebarWidth : 0))
            VStack(alignment: .leading, spacing: 0) {
                PaneHeader(title: query, icon: "magnifyingglass") {
                    if local.isLoaded, gmail != .searching {
                        Text(hits.count == 1 ? "1 result" : "\(hits.count) results")
                            .textStyle(.body).foregroundStyle(Theme.textTertiary).fixedSize()
                    }
                }
                source
                    .padding(.horizontal, 74)
                    .frame(height: 28)
                if let error = local.error {
                    EmptyState(title: "Couldn't search", message: error.localizedDescription, symbol: nil) { observeLocal() }
                } else if hits.isEmpty, gmail != .searching {
                    EmptyState(title: "No results", message: "Try different words or a Gmail operator like from: or has:attachment", symbol: "magnifyingglass")
                } else {
                    list(hits, layout)
                }
            }
        }
        .onChange(of: query, initial: true) { observeLocal() }
        .task(id: query) { await searchGmail() }
        .onAppear { labels.observe(app.store) { try Store.labels($0) } }
        .onChange(of: hits.map(\.id), initial: true) { app.visibleThreadIds = hits.map(\.id) }
    }

    private func list(_ hits: [SearchHit], _ layout: RowLayout) -> some View {
        let byId = Dictionary(uniqueKeysWithValues: labels.value.map { ($0.id, $0) })
        let terms = parsed.highlightTerms
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                        ThreadRow(thread: hit.thread, labels: byId, layout: layout, isLast: i == hits.count - 1,
                                  terms: terms, excerpt: hit.excerpt)
                            .id(hit.id)
                    }
                }
                .padding(.bottom, 24)
            }
            .onChange(of: app.focusedThreadId) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    @ViewBuilder
    private var source: some View {
        HStack(spacing: 6) {
            switch gmail {
            case .searching:
                Text("Searching Gmail…")
                DotsLoader()
            case .done:
                Text("Searched Gmail")
            case .failed:
                Text("Couldn't reach Gmail · Showing results from this Mac")
            case .idle:
                Text(parsed.needsGmail && app.isDemo
                     ? "Searched this Mac · \(parsed.unsupported.joined(separator: " ")) needs Gmail"
                     : "Searched this Mac")
            }
        }
        .textStyle(.small)
        .foregroundStyle(Theme.textTertiary)
        .lineLimit(1)
    }

    private func observeLocal() {
        let q = parsed
        local.observe(app.store) { try Store.search($0, q) }
    }

    private func searchGmail() async {
        gmail = .idle
        guard let client = app.gmail, parsed.needsGmail || local.value.isEmpty else { return }
        gmail = .searching
        do {
            let ids = try await Sync(gmail: client, store: app.store).search(query)
            guard !Task.isCancelled else { return }
            remote.observe(app.store) { try Store.threads($0, ids: ids) }
            gmail = .done
        } catch {
            if !Task.isCancelled { gmail = .failed }
        }
    }
}

/// Text with the words matching `terms` drawn as search marks (§4.7): accent semibold on `markBackground`, radius 2.
struct MarkedText: View {
    let text: String
    var terms: [String] = []

    var body: some View {
        let ranges = SearchText.marks(in: text, terms: terms)
        if ranges.isEmpty {
            Text(verbatim: text)
        } else {
            marked(ranges).textRenderer(SearchMarkRenderer())
        }
    }

    private func marked(_ ranges: [Range<String.Index>]) -> Text {
        var result = Text(verbatim: "")
        var cursor = text.startIndex
        for r in ranges {
            if cursor < r.lowerBound { result = Text("\(result)\(Text(verbatim: String(text[cursor..<r.lowerBound])))") }
            let mark = Text(verbatim: String(text[r])).fontWeight(.semibold).foregroundStyle(Theme.accent).customAttribute(SearchMark())
            result = Text("\(result)\(mark)")
            cursor = r.upperBound
        }
        if cursor < text.endIndex { result = Text("\(result)\(Text(verbatim: String(text[cursor...])))") }
        return result
    }
}

private struct SearchMark: TextAttribute {}

private struct SearchMarkRenderer: TextRenderer {
    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line where run[SearchMark.self] != nil {
                let rect = run.typographicBounds.rect.insetBy(dx: -1.5, dy: 0)
                ctx.fill(RoundedRectangle(cornerRadius: 2, style: .continuous).path(in: rect), with: .color(Theme.markBackground))
            }
            ctx.draw(line)
        }
    }
}
