import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsKeySetupAndLedger() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-EagarInMemoryStores", "YES", "-AppleLanguages", "(en-GB)"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["key.test"].waitForExistence(timeout: 15))

        // A tab is a button on iOS and a radio button on macOS.
        let ledgerTab = app.buttons["Privacy ledger"].exists ? app.buttons["Privacy ledger"] : app.radioButtons["Privacy ledger"]
        ledgerTab.tap()
        let summary = app.descendants(matching: .any)["ledger.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(summary.label.contains("Blocked attempts: 0"), summary.label)
    }
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
