import EagarCore
import EagarLedger
import EagarStore
import Foundation
import Synchronization

/// A fast ledger double that keeps drafts and completions in memory. Set `failWrites` to
/// simulate a ledger that cannot persist.
public final class InMemoryLedger: PrivacyLedgerWriting {
    public struct Entry: Sendable {
        public let id: LedgerEntryID
        public let draft: LedgerDraft
        public var completion: LedgerCompletion?
    }

    private let state = Mutex<[Entry]>([])
    private let failWrites: Bool

    public init(failWrites: Bool = false) {
        self.failWrites = failWrites
    }

    public var entries: [Entry] { state.withLock { $0 } }

    public func record(_ draft: LedgerDraft) async throws(LedgerError) -> LedgerEntryID {
        guard !failWrites else { throw .writeFailed }
        let dataClass = DataClass.max(of: draft.payloadClasses)
        let id = LedgerEntryID(rawValue: UUID(), store: StoreKind.placement(for: dataClass))
        state.withLock { $0.append(Entry(id: id, draft: draft)) }
        return id
    }

    public func complete(_ id: LedgerEntryID, with completion: LedgerCompletion) async throws(LedgerError) {
        try state.withLock { entries throws(LedgerError) in
            guard let index = entries.firstIndex(where: { $0.id == id }) else { throw .notFound }
            guard entries[index].completion == nil else { throw .alreadyCompleted }
            entries[index].completion = completion
        }
    }

    public func contains(_ id: LedgerEntryID) -> Bool {
        state.withLock { $0.contains { $0.id == id } }
    }
}
