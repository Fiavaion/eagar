import CoreGraphics
import EagarAI
import EagarCore
import Foundation

/// How the import may extract fields.
public enum TrialExtractionMode: String, Sendable, Codable, CaseIterable {
    /// The deterministic parser only: no model call of any kind.
    case parserOnly
    /// The on-device model through the router, checked against and completed by the parser.
    case onDeviceModel
}

/// Which extractor produced the draft.
public enum TrialExtractionMethod: String, Sendable, Codable, LogSafe {
    /// Parser only (mode, unavailable model, kill switch or unusable answer).
    case parser
    /// Every core field (service, price, date) came from the validated model answer.
    case onDeviceModel
    /// Some fields from the model, the rest from the parser.
    case combined

    public var logDescription: String { rawValue }
}

/// A proposed trial for Mark to confirm (FR-TRIAL-03). Nothing is stored until he does.
public struct TrialImportResult: Sendable, Hashable {
    public let draft: TrialDraft
    public let method: TrialExtractionMethod
    /// A screenshot or shared text is Mark's own data: personal.
    public let dataClass: DataClass
}

/// Share-sheet and screenshot import (FR-TRIAL-03): Vision OCR, then on-device extraction,
/// with the deterministic parser as the fallback, producing a proposed trial.
///
/// The image and its text never leave the device: OCR is Vision on device, and the only model
/// call is pinned to the on-device tier through ``AIRouter``. Nothing about the content is
/// logged; only counts and outcomes.
public struct TrialScreenshotImporter: Sendable {
    public let recognizer: any TextRecognizing
    public let parser: ReceiptParser
    public let extractor: OnDeviceTrialExtractor?
    public let mode: TrialExtractionMode
    private let log = EagarLog(.app)

    /// - Parameters:
    ///   - router: the app's router; `nil` means parser only.
    ///   - mode: `.parserOnly` makes zero model calls whatever the router.
    ///   - sourceID: the source the import is attributed to for policy and ledger, if any.
    public init(
        recognizer: any TextRecognizing = VisionTextRecognizer(),
        router: AIRouter?,
        mode: TrialExtractionMode = .onDeviceModel,
        sourceID: SourceID? = nil,
        calendar: Calendar = .current
    ) {
        self.recognizer = recognizer
        parser = ReceiptParser(calendar: calendar)
        extractor = router.map { OnDeviceTrialExtractor(router: $0, sourceID: sourceID) }
        self.mode = mode
    }

    /// Imports from encoded image data (PNG, JPEG, HEIC), e.g. from the share extension.
    public func importTrial(fromImageData data: Data) async throws(TrialImportError) -> TrialImportResult {
        try await importTrial(from: ImageDecoding.cgImage(from: data))
    }

    /// Imports from an image: OCR, then extraction.
    public func importTrial(from image: CGImage) async throws(TrialImportError) -> TrialImportResult {
        let lines = try await recognizer.recognizeText(in: image)
        guard lines.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            log.notice("trial import: no text recognised")
            throw .noText
        }
        return await extract(fromLines: lines)
    }

    /// Imports from text, e.g. text shared from another app.
    public func importTrial(fromText text: String) async -> TrialImportResult {
        await extract(fromLines: text.components(separatedBy: .newlines))
    }

    /// Extraction from recognised lines: the parser always runs; the model, if allowed,
    /// fills fields first and the parser completes whatever the model missed or got wrong.
    public func extract(fromLines lines: [String]) async -> TrialImportResult {
        let parsed = parser.parse(lines: lines)
        guard mode == .onDeviceModel, let extractor else {
            return finish(parsed, method: .parser, lineCount: lines.count)
        }
        let answer: OnDeviceTrialExtractor.Answer?
        do {
            answer = try await extractor.answer(for: lines)
        } catch {
            log.notice("trial import: on-device extraction unavailable (\(error)); using the parser")
            return finish(parsed, method: .parser, lineCount: lines.count)
        }
        guard let answer else {
            log.notice("trial import: model answer unusable; using the parser")
            return finish(parsed, method: .parser, lineCount: lines.count)
        }
        let model = OnDeviceTrialExtractor.validated(answer, against: lines, parser: parser)
        let merged = TrialDraft(
            service: model.service ?? parsed.service,
            price: model.price ?? parsed.price,
            currencyCode: model.price != nil ? (model.currencyCode ?? parsed.currencyCode) : (parsed.currencyCode ?? model.currencyCode),
            renewsAt: model.renewsAt ?? parsed.renewsAt,
            period: model.period ?? parsed.period,
            isTrial: parsed.isTrial
        )
        let fromModel = [model.service != nil, model.price != nil, model.renewsAt != nil]
        let method: TrialExtractionMethod = fromModel.allSatisfy { $0 } ? .onDeviceModel : (fromModel.contains(true) ? .combined : .parser)
        return finish(merged, method: method, lineCount: lines.count)
    }

    private func finish(_ draft: TrialDraft, method: TrialExtractionMethod, lineCount: Int) -> TrialImportResult {
        log.info("trial import: \(lineCount) lines, method \(method), core fields \(draft.hasCoreFields)")
        return TrialImportResult(draft: draft, method: method, dataClass: .personal)
    }
}
