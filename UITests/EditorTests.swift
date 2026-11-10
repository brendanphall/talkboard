import XCTest

final class EditorTests: XCTestCase {
    @MainActor
    func testEditingLabelKeepsPositionAndCancelRevertDoNotPublish() {
        let app = launch()
        let cup = app.buttons["tile-cup"]
        let original = cup.frame
        openEditor(app)
        app.buttons["edit-cell-0-0"].tap()
        replace(app.textFields["editor-label"], with: "Cup edited")
        app.buttons["editor-revert"].tap()
        XCTAssertEqual(app.textFields["editor-label"].value as? String, "Cup")
        replace(app.textFields["editor-label"], with: "Cancelled")
        app.buttons["editor-cancel"].tap()
        app.buttons["editor-cancel"].tap()
        XCTAssertEqual(cup.label,"Cup")
        app.buttons["caregiver-edit"].tap()
        app.buttons["edit-cell-0-0"].tap()
        replace(app.textFields["editor-label"], with: "Cup edited")
        replace(app.textFields["editor-spoken"], with: "A fixture phrase")
        app.buttons["editor-save"].tap()
        app.buttons["editor-cancel"].tap()
        XCTAssertEqual(cup.label,"Cup edited")
        XCTAssertEqual(cup.frame,original)
        cup.tap(); XCTAssertTrue(cup.isSelected)
    }

    @MainActor
    func testAddToEmptyCellAndBackgroundDismissesUnsavedDraft() {
        let app = launch()
        let other = app.buttons["tile-no"].frame
        openEditor(app)
        app.buttons["edit-cell-0-2"].tap()
        XCTAssertFalse(app.buttons["editor-save"].isEnabled)
        replace(app.textFields["editor-label"], with: "Fixture")
        replace(app.textFields["editor-spoken"], with: "Fixture spoken")
        app.buttons["editor-save"].tap()
        app.buttons["editor-cancel"].tap()
        XCTAssertEqual(app.buttons["tile-no"].frame,other)
        XCTAssertFalse(app.otherElements["empty-0-2"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'tile-'")).count,11)
        app.buttons["caregiver-edit"].tap()
        app.buttons["edit-cell-0-0"].tap()
        replace(app.textFields["editor-label"], with: "Never saved")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["caregiver-unlock"].waitForExistence(timeout:5))
        XCTAssertFalse(app.textFields["editor-label"].exists)
        XCTAssertEqual(app.buttons["tile-cup"].label,"Cup")
    }

    @MainActor
    func testCancellingFilePickerLeavesBoardAndEditorUnchanged() {
        let app = launch()
        openEditor(app)
        let load = app.buttons["import-pictures"]
        for _ in 0..<5 where !load.isHittable { app.swipeUp() }
        XCTAssertTrue(load.isHittable)
        load.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertFalse(app.staticTexts["editor-error"].exists)
        app.buttons["editor-cancel"].tap()
        XCTAssertEqual(app.buttons["tile-cup"].label, "Cup")
    }

    @MainActor
    private func launch() -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments=["--silent-speech-test","--caregiver-success-test"]
        app.launch();XCTAssertTrue(app.buttons["tile-cup"].waitForExistence(timeout:10));return app
    }
    @MainActor
    private func openEditor(_ app: XCUIApplication) {
        app.buttons["caregiver-unlock"].tap()
        XCTAssertTrue(app.buttons["caregiver-edit"].waitForExistence(timeout:3))
        app.buttons["caregiver-edit"].tap()
    }
    @MainActor
    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        let value=field.value as? String ?? ""
        // Empty fields report their placeholder, but excess deletes leave them empty.
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:value.count)+text)
    }
}
