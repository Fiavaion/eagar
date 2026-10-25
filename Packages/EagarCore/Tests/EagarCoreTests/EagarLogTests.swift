import Synchronization
import Testing
@testable import EagarCore

final class CapturingSink: LogSink {
    private let records = Mutex<[LogRecord]>([])
    func receive(_ record: LogRecord) { records.withLock { $0.append(record) } }
    var all: [LogRecord] { records.withLock { $0 } }
}

struct EagarLogTests {
    private enum Outcome: String, LogSafe {
        case ok
        var logDescription: String { rawValue }
    }

    @Test func rendersLiteralsAndLogSafeValues() {
        let sink = CapturingSink()
        let token = EagarLog.addSink(sink)
        defer { EagarLog.removeSink(token) }

        let count = 3
        let missing: Int? = nil
        EagarLog(.ai).info("routed \(count) items as \(DataClass.personal): \(Outcome.ok) \(missing)")

        let mine = sink.all.filter { $0.category == .ai }
        #expect(mine.last?.text == "routed 3 items as personal: ok nil")
        #expect(mine.last?.level == .info)
    }

    @Test func removedSinkReceivesNothing() {
        let sink = CapturingSink()
        EagarLog.removeSink(EagarLog.addSink(sink))
        EagarLog(.store).error("after removal")
        #expect(sink.all.isEmpty)
    }

    // A runtime String cannot become a LogMessage: `EagarLog(.ai).info(someString)` and
    // `"\(someString)"` both fail to compile because String is not LogSafe. That is the
    // control; `Tools/lint.sh` additionally forbids `print(` and `NSLog(`.
}
