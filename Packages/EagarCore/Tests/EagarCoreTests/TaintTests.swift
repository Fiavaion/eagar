import Testing
@testable import EagarCore

/// One test per `DerivationID` (FR-CORE-03). `Tools/lint.sh` checks every case has a
/// `Derivation_<case>` test somewhere in the repository.
struct TaintTests {
    private struct Item: Classified {
        let dataClass: DataClass
        let sourceID: SourceID? = nil
    }

    @Test func Derivation_aiRequestPayload() {
        #expect(Taint.derive(.aiRequestPayload, from: [DataClass.publicContent, .personal]) == .personal)
        #expect(Taint.derive(.aiRequestPayload, from: [DataClass.approvedProfile]) == .approvedProfile)
        #expect(Taint.derive(.aiRequestPayload, from: [DataClass]()) == .publicContent)
    }

    @Test func Derivation_ledgerEntry() {
        let items: [any Classified] = [Item(dataClass: .publicContent), Item(dataClass: .college)]
        #expect(Taint.derive(.ledgerEntry, from: items) == .college)
    }
}
