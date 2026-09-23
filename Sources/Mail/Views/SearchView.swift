import MailCore
import SwiftUI

/// Search results in the list pane (SPEC §4.7). Owner: palette/search feature.
struct SearchView: View {
    let query: String
    @Environment(AppState.self) private var app
    @State private var results = Live<[MailThread]>([])
    @State private var labels = Live<[MailLabel]>([])

    var body: some View {
        GeometryReader { geo in
            let layout = RowLayout(paneWidth: geo.size.width, windowWidth: geo.size.width + (app.isSidebarVisible ? Theme.Metrics.sidebarWidth : 0))
            VStack(alignment: .leading, spacing: 0) {
                PaneHeader(title: query, icon: "magnifyingglass") {
                    Text(results.value.count == 1 ? "1 result" : "\(results.value.count) results")
                        .textStyle(.body).foregroundStyle(Theme.textTertiary).fixedSize()
                }
                Text("Searched this Mac")
                    .textStyle(.small)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.leading, 74)
                    .frame(height: 28)
                if results.isLoaded, results.value.isEmpty {
                    EmptyState(title: "No results", message: "Try different words or a Gmail operator like from: or has:attachment", symbol: "magnifyingglass")
                } else {
                    let byId = Dictionary(uniqueKeysWithValues: labels.value.map { ($0.id, $0) })
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.value.enumerated()), id: \.element.id) { i, thread in
                                ThreadRow(thread: thread, labels: byId, layout: layout, isLast: i == results.value.count - 1)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: query, initial: true) {
            let q = query
            results.observe(app.store) { try Store.searchThreads($0, text: q) }
        }
        .onAppear { labels.observe(app.store) { try Store.labels($0) } }
        .onChange(of: results.value.map(\.id), initial: true) { app.visibleThreadIds = results.value.map(\.id) }
    }
}
