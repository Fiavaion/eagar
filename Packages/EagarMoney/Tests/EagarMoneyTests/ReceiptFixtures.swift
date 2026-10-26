import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import EagarMoney

/// The synthetic receipt fixtures and their expected extraction (FR-TRIAL-03).
struct ReceiptFixture: Decodable, Sendable, CustomTestStringConvertible {
    let file: String
    let service: String
    let price: String
    let currency: String
    let date: String
    /// The text rendered into the image, one line per row.
    let text: String

    var testDescription: String { file }
    var lines: [String] { text.components(separatedBy: "\n") }

    static let all: [ReceiptFixture] = {
        let url = Bundle.module.url(forResource: "expected", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode([ReceiptFixture].self, from: Data(contentsOf: url))
    }()

    func imageData() throws -> Data {
        let url = Bundle.module.url(forResource: (file as NSString).deletingPathExtension, withExtension: "png", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func cgImage() throws -> CGImage {
        try ImageDecoding.cgImage(from: imageData())
    }

    /// Whether `draft` has the expected service, price and date (the acceptance criterion's
    /// three fields; currency is reported separately).
    func matches(_ draft: TrialDraft, calendar: Calendar) -> Bool {
        draft.service == service && draft.price == Decimal(string: price) && draft.renewsAt.map { Self.dayString($0, calendar) } == date
    }

    static func dayString(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
