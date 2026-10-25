import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsKeySetupAndLedger() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-EagarInMemoryStores", "YES", "-AppleLanguages", "(en-GB)"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["key.test"].waitForExistence(timeout: 15))

        let summary = app.descendants(matching: .any)["ledger.summary"]
        open(tab: "Privacy ledger", in: app, until: summary)
        guard summary.exists else {
            // Dump the tree so a failure on a runner we can't inspect is diagnosable.
            XCTFail("ledger summary not found; element tree:\n\(app.debugDescription)")
            return
        }
        let loaded = NSPredicate(format: "label CONTAINS 'Blocked attempts: 0'")
        expectation(for: loaded, evaluatedWith: summary)
        waitForExpectations(timeout: 15)
    }
}

/// Switches tabs. The tab is a `Tab` on macOS 27, a radio button on macOS 26 and a button on
/// iOS. On macOS the focused key field can open the Passwords autofill pop-up, which swallows
/// the first click, so Escape dismisses it and the switch is retried.
@MainActor
private func open(tab label: String, in app: XCUIApplication, until target: XCUIElement) {
    for _ in 0..<3 {
        #if os(macOS)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        #endif
        let candidates = [app.tabs[label], app.buttons[label], app.radioButtons[label]].map(\.firstMatch)
        candidates.first(where: \.exists)?.tap()
        if target.waitForExistence(timeout: 5) { return }
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
