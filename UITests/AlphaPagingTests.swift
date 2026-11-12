import XCTest

final class AlphaPagingTests: XCTestCase {
    @MainActor
    func testFourthPageHasOnlyPeopleAndReturnsHome() {
        let app = XCUIApplication()
        app.launchArguments = ["--silent-speech-test"]
        app.launch()
        XCTAssertTrue(app.buttons["page-next"].waitForExistence(timeout: 5))
        let homeCup = app.buttons["tile-cup"].frame
        for _ in 0..<3 { app.buttons["page-next"].tap() }
        XCTAssertTrue(app.buttons["tile-person-one"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["page-position"].label, "Page 4 of 4")
        XCTAssertFalse(app.buttons["page-next"].isEnabled)
        XCTAssertFalse(app.buttons["tile-stop"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).count, 3)
        app.buttons["tile-person-one"].tap()
        XCTAssertTrue(app.buttons["tile-person-one"].isSelected)
        app.buttons["page-home"].tap()
        XCTAssertTrue(app.buttons["tile-cup"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["tile-cup"].frame, homeCup)
    }

    @MainActor
    func testPeopleEditingTargetsPeopleAndLeavesHomeUnchanged() {
        let app = XCUIApplication()
        app.launchArguments = ["--silent-speech-test", "--caregiver-success-test"]
        app.launch()
        XCTAssertTrue(app.buttons["page-next"].waitForExistence(timeout: 5))
        for _ in 0..<3 { app.buttons["page-next"].tap() }
        app.buttons["caregiver-unlock"].tap()
        XCTAssertTrue(app.buttons["caregiver-edit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["caregiver-edit"].label.contains("People"))
        app.buttons["caregiver-edit"].tap()
        app.buttons["edit-cell-1-1"].tap()
        let field = app.textFields["editor-label"]
        XCTAssertEqual(field.value as? String, "Person one")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "Changed person")
        app.buttons["editor-save"].tap()
        app.buttons["editor-cancel"].tap()
        XCTAssertEqual(app.buttons["tile-person-one"].label, "Changed person")
        app.buttons["page-home"].tap()
        XCTAssertTrue(app.buttons["tile-cup"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["tile-cup"].label, "Cup")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).count, 10)
        for _ in 0..<3 { app.buttons["page-next"].tap() }
        XCTAssertEqual(app.buttons["tile-person-one"].label, "Changed person")
    }

    @MainActor
    private func capturePage(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testNormalLaunchAndRelaunchOpenPagesWithoutCaregiverUnlock() {
        let app = XCUIApplication()
        app.launchArguments = ["--silent-speech-test"]
        app.launch()
        XCTAssertTrue(app.buttons["page-next"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["page-position"].label, "Page 1 of 4")
        XCTAssertTrue(app.buttons["caregiver-unlock"].exists)
        XCTAssertFalse(app.buttons["caregiver-edit"].exists)
        XCTAssertFalse(app.buttons["alpha-end"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["page-next"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPagingBoundariesHomeAndCaregiverKeepNavigationAvailable() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--silent-speech-test", "--caregiver-success-test"]
        app.launch()
        XCTAssertTrue(app.buttons["tile-cup"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["caregiver-prototype"].exists)
        let originalCup = app.buttons["tile-cup"].frame
        app.buttons["caregiver-unlock"].tap()
        XCTAssertTrue(app.buttons["caregiver-edit"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["caregiver-prototype"].exists)
        app.buttons["caregiver-lock"].tap()
        XCTAssertTrue(app.buttons["page-next"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["page-position"].label, "Page 1 of 4")
        XCTAssertFalse(app.buttons["page-previous"].isEnabled)
        XCTAssertEqual(app.buttons["page-previous"].label, "Back")
        XCTAssertGreaterThanOrEqual(app.buttons["page-next"].frame.height, 64)
        XCTAssertGreaterThan(app.buttons["page-home"].frame.minY, app.buttons["tile-help"].frame.maxY)
        let stop = app.buttons["tile-stop"].frame
        let next = app.buttons["page-next"].frame
        app.buttons["page-next"].tap()
        XCTAssertTrue(app.buttons["tile-done"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["tile-cup"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["page-position"].label, "Page 2 of 4")
        capturePage("alpha-vocabulary-page-2")
        XCTAssertEqual(app.buttons["tile-stop"].frame, stop)
        app.buttons["tile-done"].tap()
        XCTAssertTrue(app.buttons["tile-done"].isSelected)
        app.buttons["page-next"].tap()
        XCTAssertTrue(app.buttons["tile-cat"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["page-next"].isEnabled)
        XCTAssertEqual(app.descendants(matching: .any)["page-position"].label, "Page 3 of 4")
        capturePage("alpha-vocabulary-page-3")
        XCTAssertEqual(app.buttons["page-next"].frame, next)
        app.buttons["page-previous"].tap()
        XCTAssertTrue(app.buttons["tile-done"].waitForExistence(timeout: 3))
        app.buttons["page-home"].tap()
        XCTAssertTrue(app.buttons["tile-cup"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["page-position"].label, "Page 1 of 4")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "alpha-symbol-pages"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.buttons["caregiver-unlock"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["caregiver-edit"].exists)
        XCTAssertEqual(app.buttons["tile-cup"].frame, originalCup)
    }
}
