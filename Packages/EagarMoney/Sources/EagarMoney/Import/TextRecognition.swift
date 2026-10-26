import CoreGraphics
import EagarCore
import Foundation
import ImageIO
import Vision

/// Why an import could not produce a draft.
public enum TrialImportError: Error, Sendable, Equatable, LogSafe {
    /// The data is not an image ImageIO can decode.
    case unreadableImage
    /// Vision failed.
    case recognitionFailed
    /// The image contains no text.
    case noText

    public var logDescription: String {
        switch self {
        case .unreadableImage: "unreadableImage"
        case .recognitionFailed: "recognitionFailed"
        case .noText: "noText"
        }
    }
}

/// OCR behind a protocol, so tests inject recognised text (FR-TRIAL-03).
public protocol TextRecognizing: Sendable {
    /// The recognised lines, top to bottom.
    func recognizeText(in image: CGImage) async throws(TrialImportError) -> [String]
}

/// Apple Vision text recognition, on device.
public struct VisionTextRecognizer: TextRecognizing {
    public let languages: [Locale.Language]

    public init(languages: [Locale.Language] = [Locale.Language(identifier: "en-GB"), Locale.Language(identifier: "en-US")]) {
        self.languages = languages
    }

    public func recognizeText(in image: CGImage) async throws(TrialImportError) -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(on: image)
        } catch {
            throw .recognitionFailed
        }
        // Vision's normalised coordinates have their origin at the bottom left: higher is first.
        return observations
            .sorted { lhs, rhs in
                let l = lhs.boundingBox.cgRect, r = rhs.boundingBox.cgRect
                return abs(l.midY - r.midY) > 0.005 ? l.midY > r.midY : l.minX < r.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
    }
}

enum ImageDecoding {
    /// Decodes PNG, JPEG, HEIC and the other formats ImageIO reads.
    static func cgImage(from data: Data) throws(TrialImportError) -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw .unreadableImage }
        return image
    }
}
