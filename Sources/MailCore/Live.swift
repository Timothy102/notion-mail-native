import Foundation
import GRDB
import Observation

/// A database query whose result views read directly and which re-renders on every change.
///
///     @State private var threads = Live<[MailThread]>([])
///     .onChange(of: app.mailbox, initial: true) { threads.observe(app.store) { try Store.threads($0, in: app.mailbox) } }
///
/// The first value is fetched synchronously, so a view never renders an empty frame before its data.
@MainActor @Observable
public final class Live<Value: Sendable> {
    public private(set) var value: Value
    public private(set) var isLoaded = false
    public private(set) var error: (any Error)?
    @ObservationIgnored private var cancellable: AnyDatabaseCancellable?

    public init(_ initial: Value) {
        value = initial
    }

    public func observe(_ store: Store, _ fetch: @escaping @Sendable (Database) throws -> Value) {
        cancellable = ValueObservation.tracking(fetch).start(
            in: store.db, scheduling: .immediate,
            onError: { [weak self] in self?.error = $0 },
            onChange: { [weak self] in
                self?.value = $0
                self?.isLoaded = true
                self?.error = nil
            })
    }

    public func stop() {
        cancellable = nil
    }
}
