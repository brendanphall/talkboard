import XCTest

final class PublicDemoTests: XCTestCase {
    @MainActor
    func testPublicDemoHasGenericArtworkEmptyPeopleAndCredits() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--silent-speech-test", "--public-demo-test"]
        app.launch()
        XCTAssertTrue(app.buttons["tile-dog"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).count, 11)
        XCTAssertTrue(app.buttons["tile-yes"].exists)
        XCTAssertTrue(app.buttons["tile-go"].exists)
        app.buttons["about-demo"].tap()
        XCTAssertTrue(app.staticTexts["artwork-credits"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["artwork-credits"].label.contains("CC BY-NC-SA 4.0"))
        app.buttons["about-done"].tap()
        capture("public-home")
        app.buttons["page-next"].tap()
        XCTAssertTrue(app.buttons["tile-done"].waitForExistence(timeout: 3))
        capture("public-vocabulary")
        app.buttons["page-next"].tap()
        app.buttons["page-next"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).count, 0)
        XCTAssertEqual(app.descendants(matching: .any)["page-position"].label, "Page 4 of 4")
        app.buttons["page-home"].tap()
        app.buttons["learning-open"].tap()
        XCTAssertTrue(app.buttons["letter-A"].waitForExistence(timeout: 3))
        capture("public-alphabet")
        app.buttons["learning-numbers"].tap()
        XCTAssertTrue(app.buttons["number-20"].exists)
        capture("public-numbers")
    }

    @MainActor
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
