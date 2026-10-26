import Foundation

/// Subscription services the receipt parser recognises by name. Aliases are matched
/// case-insensitively on word boundaries; the longest alias on the earliest line wins.
/// Generic words ("Apple", "App Store", "Receipt") are deliberately absent.
public struct KnownMerchant: Sendable, Hashable {
    public let name: String
    public let aliases: [String]

    public init(_ name: String, aliases: [String] = []) {
        self.name = name
        self.aliases = ([name] + aliases).map { $0.lowercased() }
    }
}

extension KnownMerchant {
    /// The built-in list. Names only: no cancel URLs, which change too often to hard-code
    /// (cancel falls back to the App Store page, FR-TRIAL-05).
    public static let builtIn: [KnownMerchant] = [
        KnownMerchant("Netflix"),
        KnownMerchant("Spotify"),
        KnownMerchant("Disney+", aliases: ["Disney Plus", "Disney"]),
        KnownMerchant("Apple TV+", aliases: ["Apple TV"]),
        KnownMerchant("Apple Music"),
        KnownMerchant("Apple One"),
        KnownMerchant("Apple Arcade"),
        KnownMerchant("iCloud+", aliases: ["iCloud"]),
        KnownMerchant("Amazon Prime", aliases: ["Prime Video", "Amazon Prime Video"]),
        KnownMerchant("Audible"),
        KnownMerchant("Kindle Unlimited"),
        KnownMerchant("Headspace"),
        KnownMerchant("Calm"),
        KnownMerchant("Duolingo", aliases: ["Super Duolingo", "Duolingo Max"]),
        KnownMerchant("Adobe Creative Cloud", aliases: ["Creative Cloud", "Adobe"]),
        KnownMerchant("Microsoft 365", aliases: ["Office 365"]),
        KnownMerchant("Google One"),
        KnownMerchant("Dropbox"),
        KnownMerchant("Notion"),
        KnownMerchant("Medium"),
        KnownMerchant("Patreon"),
        KnownMerchant("Strava"),
        KnownMerchant("NOW TV"),
        KnownMerchant("Paramount+", aliases: ["Paramount Plus"]),
        KnownMerchant("Crunchyroll"),
        KnownMerchant("Deezer"),
        KnownMerchant("Tidal"),
        KnownMerchant("ChatGPT Plus", aliases: ["ChatGPT"]),
        KnownMerchant("Claude Pro"),
        KnownMerchant("1Password"),
        KnownMerchant("NordVPN"),
        KnownMerchant("Canva", aliases: ["Canva Pro"]),
        KnownMerchant("Figma"),
        KnownMerchant("Babbel"),
        KnownMerchant("The Irish Times", aliases: ["Irish Times"]),
        KnownMerchant("The Guardian"),
        KnownMerchant("The New York Times", aliases: ["New York Times", "NYTimes"]),
        KnownMerchant("Substack"),
    ]
}
