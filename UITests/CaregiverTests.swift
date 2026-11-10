import XCTest

final class CaregiverTests: XCTestCase {
    @MainActor
    func testUnlockLockAndBackgroundKeepBoardAvailable() {
        let app = launch("--caregiver-success-test")
        XCTAssertFalse(app.staticTexts["caregiver-unlocked"].exists)
        app.buttons["caregiver-unlock"].tap()
        XCTAssertTrue(app.staticTexts["caregiver-unlocked"].waitForExistence(timeout: 3))
        let cup = app.buttons["tile-cup"]
        cup.tap()
        XCTAssertTrue(cup.isSelected)
        app.buttons["caregiver-lock"].tap()
        XCTAssertTrue(app.buttons["caregiver-unlock"].exists)
        app.buttons["caregiver-unlock"].tap()
        XCTAssertTrue(app.staticTexts["caregiver-unlocked"].waitForExistence(timeout: 3))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["caregiver-unlock"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["caregiver-unlocked"].exists)
        cup.tap()
        XCTAssertTrue(cup.isSelected)
    }

    @MainActor
    func testCancelPendingAuthenticationReturnsToSpeakingBoard() {
        let app = launch("--caregiver-pending-test")
        app.buttons["caregiver-unlock"].tap()
        XCTAssertTrue(app.buttons["caregiver-cancel"].waitForExistence(timeout: 3))
        app.buttons["caregiver-cancel"].tap()
        XCTAssertTrue(app.buttons["caregiver-unlock"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["caregiver-unlocked"].exists)
        app.buttons["tile-stop"].tap()
        XCTAssertTrue(app.buttons["tile-stop"].isSelected)
    }

    @MainActor
    func testFailedAuthenticationLeavesSpeechAndRetryAvailable() {
        let app = launch("--caregiver-failure-test")
        app.buttons["caregiver-unlock"].tap()
        XCTAssertTrue(app.staticTexts["caregiver-failed"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["caregiver-unlocked"].exists)
        app.buttons["tile-help"].tap()
        XCTAssertTrue(app.buttons["tile-help"].isSelected)
        XCTAssertTrue(app.buttons["caregiver-unlock"].isHittable)
    }

    @MainActor
    func testGuidedAccessHidesCaregiverControlsAndKeepsSpeech() {
        let app = launch("--caregiver-success-test", "--guided-access-test")
        XCTAssertFalse(app.buttons["caregiver-unlock"].exists)
        XCTAssertFalse(app.staticTexts["caregiver-unlocked"].exists)
        app.buttons["tile-no"].tap()
        XCTAssertTrue(app.buttons["tile-no"].isSelected)
    }

    @MainActor
    private func launch(_ arguments: String...) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--silent-speech-test"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["tile-cup"].waitForExistence(timeout: 10))
        return app
    }
}
