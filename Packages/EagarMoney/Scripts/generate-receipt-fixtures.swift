#!/usr/bin/env swift
// Renders the synthetic receipt and screenshot fixtures for EagarMoney's import tests
// (FR-TRIAL-03). Every service name, amount and date below is invented test data; nothing
// comes from a real receipt or account.
//
// Usage (from the repository root):
//   swift Packages/EagarMoney/Scripts/generate-receipt-fixtures.swift
// Output: Packages/EagarMoney/Tests/EagarMoneyTests/Fixtures/receipt-NN.png and expected.json.
// The output is deterministic for a given macOS font set; the PNGs are committed so tests
// never depend on this script running.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Fixture {
    let name: String
    let lines: [String]
    /// Expected extraction: service, price (as written with a dot), ISO currency, yyyy-MM-dd.
    let service: String
    let price: String
    let currency: String
    let date: String
    /// Dark-mode screenshot style.
    var dark = false
}

let fixtures: [Fixture] = [
    Fixture(name: "receipt-01", lines: [
        "Receipt", "Apple Account: someone@example.invalid", "Date: 26 Oct 2026",
        "Order ID: MX4TQ0ZZ91", "Document No.: 100000000001",
        "App Store", "Calm Premium (Yearly)", "Renews 3 Dec 2026", "€69.99",
        "Subtotal €56.90", "VAT charged at 23% €13.09", "Total €69.99",
    ], service: "Calm", price: "69.99", currency: "EUR", date: "2026-12-03"),
    Fixture(name: "receipt-02", lines: [
        "NETFLIX", "Your free trial ends on 12/11/2026",
        "After your trial, your plan costs £10.99/month.", "Cancel anytime in Account settings.",
    ], service: "Netflix", price: "10.99", currency: "GBP", date: "2026-11-12"),
    Fixture(name: "receipt-03", lines: [
        "Spotify", "Premium Individual", "Your trial ends 5 Nov 2026.",
        "Then €11.99/month. Cancel anytime.",
    ], service: "Spotify", price: "11.99", currency: "EUR", date: "2026-11-05", dark: true),
    Fixture(name: "receipt-04", lines: [
        "Disney+", "Welcome to Disney+ Premium", "Free trial started October 27, 2026",
        "$13.99/mo starting November 20, 2026", "Plus applicable taxes",
    ], service: "Disney+", price: "13.99", currency: "USD", date: "2026-11-20"),
    Fixture(name: "receipt-05", lines: [
        "Headspace", "Subscription summary", "Trial ends: 2026-11-30",
        "Price: EUR 12.99 per month", "Payment method: card ending 0000",
    ], service: "Headspace", price: "12.99", currency: "EUR", date: "2026-11-30"),
    Fixture(name: "receipt-06", lines: [
        "Receipt", "Apple Account", "Invoice date: 26.10.2026", "Apple TV+",
        "Monthly", "Renews 01.12.2026", "£8.99", "Total £8.99",
    ], service: "Apple TV+", price: "8.99", currency: "GBP", date: "2026-12-01", dark: true),
    Fixture(name: "receipt-07", lines: [
        "duolingo", "Super Duolingo", "Free trial: 14 days",
        "Billing starts 9 December 2026", "€9.99 / month after trial",
    ], service: "Duolingo", price: "9.99", currency: "EUR", date: "2026-12-09"),
    Fixture(name: "receipt-08", lines: [
        "Adobe", "Creative Cloud All Apps", "Order number 0000000000",
        "Plan price US$ 59.99/mo", "Next billing date Dec 15, 2026",
    ], service: "Adobe Creative Cloud", price: "59.99", currency: "USD", date: "2026-12-15"),
    Fixture(name: "receipt-09", lines: [
        "audible", "Your free trial is active",
        "£8.99 a month after your free trial ends on 28 November 2026.",
        "Cancel at least a day before to avoid charges.",
    ], service: "Audible", price: "8.99", currency: "GBP", date: "2026-11-28"),
    Fixture(name: "receipt-10", lines: [
        "Medium", "Membership confirmed", "Purchased on 10/21/2026",
        "Medium membership $5.00 / month", "Renews on 11/21/2026",
    ], service: "Medium", price: "5.00", currency: "USD", date: "2026-11-21"),
    Fixture(name: "receipt-11", lines: [
        "Receipt", "Apple Account", "Date: 26 Oct 2026", "iCloud+",
        "iCloud+ with 200 GB (Monthly)", "Renews 26 Nov 2026", "2,99 €",
        "VAT 0,56 €", "Total 2,99 €",
    ], service: "iCloud+", price: "2.99", currency: "EUR", date: "2026-11-26"),
    Fixture(name: "receipt-12", lines: [
        "Notion", "Plus plan", "Billed annually",
        "€96.00/year", "Your plan renews on 2 January 2027.",
    ], service: "Notion", price: "96.00", currency: "EUR", date: "2027-01-02", dark: true),
]

let width = 900
let lineHeight = 64
let margin = 48

func render(_ fixture: Fixture, to url: URL) throws {
    let height = margin * 2 + lineHeight * fixture.lines.count
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }
    let background: CGColor = fixture.dark ? CGColor(gray: 0.1, alpha: 1) : CGColor(gray: 1, alpha: 1)
    let foreground: CGColor = fixture.dark ? CGColor(gray: 0.95, alpha: 1) : CGColor(gray: 0.05, alpha: 1)
    context.setFillColor(background)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    for (index, text) in fixture.lines.enumerated() {
        let isHeader = index == 0
        let font = CTFontCreateWithName((isHeader ? "Helvetica-Bold" : "Helvetica") as CFString, isHeader ? 40 : 30, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): foreground,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        // Core Graphics' origin is bottom-left; lines run top to bottom.
        let y = height - margin - lineHeight * (index + 1) + 18
        context.textPosition = CGPoint(x: margin, y: y)
        CTLineDraw(line, context)
    }

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let packageURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outURL = packageURL.appending(path: "Tests/EagarMoneyTests/Fixtures", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

var expected: [[String: String]] = []
for fixture in fixtures {
    try render(fixture, to: outURL.appending(path: "\(fixture.name).png"))
    expected.append([
        "file": "\(fixture.name).png", "service": fixture.service, "price": fixture.price,
        "currency": fixture.currency, "date": fixture.date, "text": fixture.lines.joined(separator: "\n"),
    ])
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(expected).write(to: outURL.appending(path: "expected.json"))
FileHandle.standardError.write(Data("wrote \(fixtures.count) fixtures to \(outURL.path)\n".utf8))
