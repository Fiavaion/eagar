import EagarCore
import Foundation

/// A proposed trial waiting for Mark's confirmation: written by the share extension, picked
/// up by the app when it becomes active (FR-TRIAL-03). Personal: a screenshot or shared text
/// is Mark's own data. Nothing is stored as a `Trial` until he confirms.
public struct PendingTrialImport: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let draft: TrialDraft
    public let method: TrialExtractionMethod
    public let createdAt: Date

    public init(id: UUID = UUID(), draft: TrialDraft, method: TrialExtractionMethod, createdAt: Date) {
        self.id = id
        self.draft = draft
        self.method = method
        self.createdAt = createdAt
    }
}

/// Why a pending import could not be written or read.
public enum PendingTrialImportError: Error, Sendable, Equatable, LogSafe {
    /// No App Group container (unsigned build): the extension cannot hand anything over.
    case noContainer
    case writeFailed
    case readFailed

    public var logDescription: String {
        switch self {
        case .noContainer: "noContainer"
        case .writeFailed: "writeFailed"
        case .readFailed: "readFailed"
        }
    }
}

/// One JSON file per pending import in a directory of the App Group container.
public struct PendingTrialImportStore: Sendable {
    /// The directory holding the files; `nil` when there is no App Group (unsigned builds).
    public let directory: URL?

    public init(directory: URL?) {
        self.directory = directory
    }

    /// The shared store the share extension and the app both use.
    public static var appGroup: PendingTrialImportStore {
        PendingTrialImportStore(directory: EagarAppGroup.containerURL?.appending(path: "PendingTrialImports", directoryHint: .isDirectory))
    }

    public var isAvailable: Bool { directory != nil }

    /// Writes `item` atomically.
    public func save(_ item: PendingTrialImport) throws(PendingTrialImportError) {
        guard let directory else { throw .noContainer }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(item).write(to: fileURL(for: item.id, in: directory), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw .writeFailed
        }
    }

    /// Every pending import, oldest first. Unreadable files are skipped and removed, so one
    /// corrupt hand-over never blocks the others.
    public func all() -> [PendingTrialImport] {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var items: [PendingTrialImport] = []
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url), let item = try? decoder.decode(PendingTrialImport.self, from: data) {
                items.append(item)
            } else {
                EagarLog(.money).notice("an unreadable pending trial import was removed")
                try? FileManager.default.removeItem(at: url)
            }
        }
        return items.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    /// Removes the import once Mark has confirmed or discarded it.
    public func remove(id: UUID) {
        guard let directory else { return }
        do {
            try FileManager.default.removeItem(at: fileURL(for: id, in: directory))
        } catch {
            EagarLog(.money).notice("a pending trial import could not be removed")
        }
    }

    private func fileURL(for id: UUID, in directory: URL) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
