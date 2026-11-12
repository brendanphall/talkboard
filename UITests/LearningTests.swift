import XCTest

final class LearningTests: XCTestCase {
    @MainActor
    func testLettersNumbersAndHomeKeepCommunicationLayout() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--silent-speech-test"]
        app.launch()
        XCTAssertTrue(app.buttons["tile-cup"].waitForExistence(timeout: 10))
        let cup = app.buttons["tile-cup"].frame
        let home = app.buttons["page-home"].frame
        let back = app.buttons["page-previous"].frame
        let next = app.buttons["page-next"].frame
        let entry = app.buttons["learning-open"]
        guard entry.waitForExistence(timeout: 3) else { XCTFail("Missing ABC / 123 entry"); return }
        XCTAssertLessThan(entry.frame.maxX, back.midX - 32)
        entry.tap()
        XCTAssertTrue(app.buttons["letter-A"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'letter-'")).count, 26)
        XCTAssertFalse(app.buttons["tile-cup"].exists)
        XCTAssertEqual(app.buttons["page-home"].frame, home)
        XCTAssertEqual(app.buttons["page-previous"].frame, back)
        XCTAssertEqual(app.buttons["page-next"].frame, next)
        for letter in ["A", "I", "Z"] {
            app.buttons["letter-\(letter)"].tap()
            XCTAssertTrue(app.buttons["letter-\(letter)"].isSelected)
        }
        let alphabetShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        alphabetShot.name = "ABC123-alphabet"; alphabetShot.lifetime = .keepAlways; add(alphabetShot)
        app.buttons["learning-numbers"].tap()
        XCTAssertTrue(app.buttons["number-20"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["letter-A"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'number-'")).count, 20)
        app.buttons["number-20"].tap()
        XCTAssertTrue(app.buttons["number-20"].isSelected)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "ABC123-numbers"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["page-home"].tap()
        XCTAssertTrue(app.buttons["tile-cup"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["tile-cup"].frame, cup)
        app.buttons["page-next"].tap()
        entry.tap()
        // The broad Back area beside the arrow remains usable.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: home.minX - 40 - app.frame.minX, dy: home.midY - app.frame.minY)).tap()
        XCTAssertTrue(app.buttons["tile-done"].waitForExistence(timeout: 3))
    }
}
