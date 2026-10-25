import Testing
@testable import EagarCore

struct DataClassTests {
    @Test func orderingIsAscendingRestrictiveness() {
        #expect(DataClass.allCases == [.publicContent, .approvedProfile, .personal, .college])
        #expect(DataClass.allCases.sorted() == DataClass.allCases)
        #expect(DataClass.publicContent < .approvedProfile)
        #expect(DataClass.approvedProfile < .personal)
        #expect(DataClass.personal < .college)
    }

    @Test func maxOfEmptyIsPublicContent() {
        #expect(DataClass.max(of: []) == .publicContent)
    }

    @Test(arguments: DataClass.allCases, DataClass.allCases)
    func maxOfPairIsMoreRestrictive(a: DataClass, b: DataClass) {
        let result = DataClass.max(of: [a, b])
        #expect(result >= a && result >= b)
        #expect(result == a || result == b)
    }

    /// B-2 (taint): one college input makes the whole payload college, whatever else is mixed in.
    @Test(arguments: 0..<50)
    func Boundary_B2_collegeTaintsAnyMix(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed))
        let others: [DataClass] = [.publicContent, .approvedProfile, .personal]
        var mix = (0..<Int(rng.next() % 20)).map { _ in others[Int(rng.next() % 3)] }
        mix.insert(.college, at: Int(rng.next() % UInt64(mix.count + 1)))
        #expect(DataClass.max(of: mix) == .college)
        #expect(Taint.derive(.aiRequestPayload, from: mix) == .college)
    }

    @Test func onlyCollegeIsLocalOnly() {
        #expect(DataClass.allCases.filter(\.isLocalOnly) == [.college])
    }

    @Test func rawValuesMatchEagarRulesSchema() {
        // Appendix F enum; changing a raw value breaks every persisted record and rules file.
        #expect(DataClass.allCases.map(\.rawValue) == ["publicContent", "approvedProfile", "personal", "college"])
    }
}

/// Small deterministic generator so tests are reproducible without a dependency.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
