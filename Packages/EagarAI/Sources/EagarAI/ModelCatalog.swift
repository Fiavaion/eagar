import Foundation

/// Claude model IDs and prices, from the bundled `models.json` (FR-AI-08). Never hard-coded.
public struct ModelCatalog: Sendable, Decodable {
    public struct PriceTier: Sendable, Decodable, Equatable {
        /// Upper bound on prompt tokens for this tier; `nil` for the last tier.
        public let maxPromptTokens: Int?
        public let inputPerMTok: Decimal
        public let outputPerMTok: Decimal
        public let cacheReadPerMTok: Decimal
        public let cacheWrite5mPerMTok: Decimal
    }

    public struct Model: Sendable, Decodable, Identifiable {
        public let id: ModelID
        public let displayName: String
        /// Fable is listed but not offered by default (BD-07).
        public let offered: Bool
        public let pricing: [PriceTier]
        public let note: String?
    }

    public let schemaVersion: Int
    public let verifiedOn: String
    public let defaults: [ModelClass: ModelID]
    public let models: [Model]

    private enum CodingKeys: String, CodingKey { case schemaVersion, verifiedOn, defaults, models }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        verifiedOn = try container.decode(String.self, forKey: .verifiedOn)
        models = try container.decode([Model].self, forKey: .models)
        let rawDefaults = try container.decode([String: String].self, forKey: .defaults)
        var defaults: [ModelClass: ModelID] = [:]
        for (key, value) in rawDefaults {
            guard let modelClass = ModelClass(rawValue: key) else { continue }
            defaults[modelClass] = ModelID(value)
        }
        self.defaults = defaults
    }

    /// Loads the catalogue from `data`, e.g. an edited copy in Settings › Advanced.
    public static func load(from data: Data) throws -> ModelCatalog {
        try JSONDecoder().decode(ModelCatalog.self, from: data)
    }

    /// The catalogue shipped with the app.
    public static func bundled() throws -> ModelCatalog {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try load(from: Data(contentsOf: url))
    }

    public func model(_ id: ModelID) -> Model? {
        models.first { $0.id == id }
    }

    /// Models shown in the picker (Fable hidden unless enabled).
    public var offeredModels: [Model] { models.filter(\.offered) }

    public func defaultModel(for purpose: AIPurpose) -> ModelID? {
        defaults[purpose.modelClass]
    }

    /// Cost in millionths of a US dollar, rounded to the nearest. `nil` for an unknown model.
    public func costMicroUSD(model id: ModelID, usage: LLMUsage) -> Int64? {
        guard let tiers = model(id)?.pricing,
              let tier = tiers.first(where: { $0.maxPromptTokens.map { usage.promptTokens <= $0 } ?? true })
        else { return nil }
        // $/MTok × tokens = µ$ exactly, because 1 µ$ per token is $1/MTok.
        var total = tier.inputPerMTok * Decimal(usage.inputTokens)
        total += tier.outputPerMTok * Decimal(usage.outputTokens)
        total += tier.cacheReadPerMTok * Decimal(usage.cacheReadTokens)
        total += tier.cacheWrite5mPerMTok * Decimal(usage.cacheWriteTokens)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &total, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
