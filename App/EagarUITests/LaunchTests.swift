import XCTest

@MainActor
private func launch(_ arguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-EagarInMemoryStores", "YES", "-EagarSkipOnboarding", "YES", "-AppleLanguages", "(en-GB)"] + arguments
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

/// Taps a tab by name. On iPhone, tabs past the fifth (M2 added Subscriptions and People)
/// sit behind "More" or the sidebar-adaptable tab bar's sidebar.
@MainActor
private func openTab(_ name: String, in app: XCUIApplication) {
    let direct = app.buttons[name].firstMatch
    if direct.waitForExistence(timeout: 3), direct.isHittable {
        direct.tap()
        return
    }
    for overflow in ["More", "Show Sidebar", "Sidebar"] {
        let button = app.buttons[overflow].firstMatch
        if button.exists, button.isHittable {
            button.tap()
            break
        }
    }
    let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 5), "tab \(name) not found; element tree:\n\(app.debugDescription)")
    item.tap()
}

final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsKeySetup() throws {
        let app = launch(["-EagarInitialTab", "key"])
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
        let app = launch(["-EagarInitialTab", "key"])
        XCTAssertTrue(app.descendants(matching: .any)["key.test"].waitForExistence(timeout: 15))
        openTab("Privacy ledger", in: app)
        expectSummary(in: app)
    }
    #endif

    /// Today is the default tab: the brief shows the fake calendar's items, with the boundary
    /// badge on college items (FR-BRIEF-01, BD-04).
    @MainActor
    func testTodayShowsBriefAndCollegeBadge() throws {
        let app = launch(["-EagarFakeCalendar", "YES"])
        let item = app.descendants(matching: .any).matching(identifier: "brief.item").firstMatch
        guard item.waitForExistence(timeout: 15) else {
            XCTFail("no brief item; element tree:\n\(app.debugDescription)")
            return
        }
        let badge = app.descendants(matching: .any).matching(identifier: "badge.college").firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(badge.label, "College, stays on your devices")
    }

    #if os(iOS)
    /// The first-run flow appears without `-EagarSkipOnboarding` and can be skipped (FR-CORE-05).
    /// iOS only, like the tab test above: clicks are unreliable on the macOS 27 CI runner.
    @MainActor
    func testFirstRunFlowCanBeSkipped() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-EagarInMemoryStores", "YES", "-EagarFakeCalendar", "YES", "-AppleLanguages", "(en-GB)",
            "-onboarding.completed", "NO",
        ]
        app.launch()
        let skip = app.descendants(matching: .any)["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        skip.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "brief.item").firstMatch.waitForExistence(timeout: 15))
    }
    #endif
}

final class IrishPseudoLocaleTests: XCTestCase {
    /// NFR-L10N-02: the `ga` locale builds and loads (pseudo-localised until translated).
    @MainActor
    func testIrishPseudoLocaleLoads() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-EagarInMemoryStores", "YES", "-EagarSkipOnboarding", "YES", "-EagarInitialTab", "key",
            "-AppleLanguages", "(ga)", "-AppleLocale", "ga_IE",
        ]
        app.launch()
        // The first line is always on screen; longer pseudo strings push later rows out of the lazy Form.
        let intro = app.descendants(matching: .any)["key.intro"]
        XCTAssertTrue(intro.waitForExistence(timeout: 15))
        // Static text is exposed as the label on iOS and as the value on macOS.
        let text = intro.label + ((intro.value as? String) ?? "")
        XCTAssertTrue(text.contains("·]"), text)
    }
}
