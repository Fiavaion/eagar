import EagarCore
import EagarMoney
import Foundation
import UniformTypeIdentifiers

/// What the extension shows.
enum ShareImportState: Equatable {
    case reading
    /// Handed over to the app; `service` is the proposed name, if one was found.
    case saved(service: String?)
    /// Unsigned builds have no App Group, so nothing can be handed over.
    case noContainer
    case nothingFound
    case failed
}

/// Reads one shared image or text in parser-only mode and hands the proposal to the app
/// (FR-TRIAL-03). The extension has no router, so it makes no model call of any kind; the
/// image never leaves the device and nothing about it is logged.
@MainActor
enum ShareImport {
    static func run(_ attachments: [NSItemProvider], store: PendingTrialImportStore = .appGroup) async -> ShareImportState {
        guard store.isAvailable else { return .noContainer }
        let importer = TrialScreenshotImporter(router: nil, mode: .parserOnly)
        let result: TrialImportResult
        do {
            if let image = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
                result = try await importer.importTrial(fromImageData: try await loadData(image, type: .image))
            } else if let text = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
                result = await importer.importTrial(fromText: try await loadText(text))
            } else {
                return .nothingFound
            }
        } catch {
            EagarLog(.money).notice("share import could not read the item")
            return .nothingFound
        }
        do {
            try store.save(PendingTrialImport(draft: result.draft, method: result.method, createdAt: Date()))
        } catch {
            EagarLog(.money).error("share import hand-over failed: \(error)")
            return .failed
        }
        return .saved(service: result.draft.service)
    }

    private static func loadText(_ provider: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: String.self) { continuation.resume(with: $0) }
        }
    }

    private static func loadData(_ provider: NSItemProvider, type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }
}
