import XCTest

private func launch(_ arguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-EagarInMemoryStores", "YES", "-AppleLanguages", "(en-GB)"] + arguments
    app.launch()
    return app
}

@MainActor
private func expectSummary(in app: XCUIApplication) {
    let summary = app.descendants(matching: .any)["ledger.summary"]
    guard summary.waitForExistence(timeout: 15) else {
        // Dump the tree so a failure on a runner we can't inspect is diagnosable.
        XCTFail("ledger summary not found; element tree:\n\(app.debugDescription)")
        return
    }
    let loaded = NSPredicate(format: "label CONTAINS 'Blocked attempts: 0'")
    XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: summary)], timeout: 15)
    XCTAssertTrue(summary.label.contains("Blocked attempts: 0"), summary.label)
}

final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsKeySetup() throws {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["key.test"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testLedgerShowsSummary() throws {
        expectSummary(in: launch(["-EagarInitialTab", "ledger"]))
    }

    #if os(iOS)
    /// Tab switching by tap. iOS only: on the macOS 27 CI runner the window is not treated as
    /// active, so clicks on toolbar tabs do not switch them (it works on a real Mac).
    @MainActor
    func testTappingLedgerTabShowsSummary() throws {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["key.test"].waitForExistence(timeout: 15))
        app.buttons["Privacy ledger"].firstMatch.tap()
        expectSummary(in: app)
    }
    #endif
}

final class IrishPseudoLocaleTests: XCTestCase {
    /// NFR-L10N-02: the `ga` locale builds and loads (pseudo-localised until translated).
    @MainActor
    func testIrishPseudoLocaleLoads() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-EagarInMemoryStores", "YES", "-AppleLanguages", "(ga)", "-AppleLocale", "ga_IE"]
        app.launch()
        // The first line is always on screen; longer pseudo strings push later rows out of the lazy Form.
        let intro = app.descendants(matching: .any)["key.intro"]
        XCTAssertTrue(intro.waitForExistence(timeout: 15))
        // Static text is exposed as the label on iOS and as the value on macOS.
        let text = intro.label + ((intro.value as? String) ?? "")
        XCTAssertTrue(text.contains("·]"), text)
    }
}
