import EagarCalendar
import Foundation
import Synchronization

/// In-memory `NotificationScheduling` for tests. Tracks pending requests and records calls.
public final class SpyNotificationScheduler: NotificationScheduling {
    public struct State: Sendable {
        public var pending: [String: PlannedNotification] = [:]
        /// Identifiers pending before the test, which have no plan entry.
        public var foreignIdentifiers: [String] = []
        public var added: [PlannedNotification] = []
        public var removed: [String] = []
        public var authorizationRequests = 0
        public var grantAuthorization = true
        public var failAdd = false
    }

    public struct AddFailed: Error {}

    public let state: Mutex<State>

    public init(foreignPending: [String] = []) {
        var initial = State()
        initial.foreignIdentifiers = foreignPending
        state = Mutex(initial)
    }

    public func pendingIdentifiers() async -> [String] {
        state.withLock { Array($0.pending.keys) + $0.foreignIdentifiers }
    }

    public func add(_ planned: PlannedNotification) async throws {
        try state.withLock { s in
            if s.failAdd { throw AddFailed() }
            s.pending[planned.id] = planned
            s.added.append(planned)
        }
    }

    public func remove(identifiers: [String]) async {
        state.withLock { s in
            s.removed.append(contentsOf: identifiers)
            for id in identifiers {
                s.pending[id] = nil
                s.foreignIdentifiers.removeAll { $0 == id }
            }
        }
    }

    public func requestAuthorization() async throws -> Bool {
        state.withLock { s in
            s.authorizationRequests += 1
            return s.grantAuthorization
        }
    }
}
