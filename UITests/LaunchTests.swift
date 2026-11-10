import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testBoardKeepsStoredRowsColumnsAndEmptyCells() {
        let app = launchBoard()
        let cup = app.buttons["tile-cup"]
        XCTAssertTrue(cup.waitForExistence(timeout: 10))
        let stop = app.buttons["tile-stop"]
        let park = app.buttons["tile-park"]
        let help = app.buttons["tile-help"]
        XCTAssertEqual(cup.frame.minY, stop.frame.minY, accuracy: 1)
        XCTAssertLessThan(cup.frame.minX, stop.frame.minX)
        XCTAssertEqual(cup.frame.minX, park.frame.minX, accuracy: 1)
        XCTAssertLessThan(cup.frame.minY, park.frame.minY)
        XCTAssertLessThan(park.frame.minY, help.frame.minY)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).count, 10)
        let empty = app.otherElements["empty-0-2"]
        XCTAssertTrue(empty.exists)
        XCTAssertEqual(empty.frame.minY, cup.frame.minY, accuracy: 1)
        XCTAssertGreaterThan(empty.frame.minX, stop.frame.minX)
        XCTAssertLessThan(empty.frame.minX, app.buttons["tile-no"].frame.minX)
        XCTAssertEqual(app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'empty-'")).count, 5)
        XCTAssertLessThan(app.otherElements["message-band"].frame.maxY, cup.frame.minY)
        let columns = [cup.frame.minX, stop.frame.minX, empty.frame.minX,
                       app.buttons["tile-no"].frame.minX, app.buttons["tile-open"].frame.minX]
        let rows = [cup.frame.minY, park.frame.minY, help.frame.minY]
        let expected: [(String, Int, Int)] = [
            ("cup", 0, 0), ("stop", 0, 1), ("no", 0, 3), ("open", 0, 4),
            ("park", 1, 0), ("go", 1, 2), ("more", 1, 4),
            ("help", 2, 0), ("ball", 2, 1), ("book", 2, 3),
            ("0-2", 0, 2), ("1-1", 1, 1), ("1-3", 1, 3), ("2-2", 2, 2), ("2-4", 2, 4),
        ]
        let frames = boardFrames(app)
        for (id, row, column) in expected {
            let frame = frames[id]!
            XCTAssertEqual(frame.minX, columns[column], accuracy: 1, id)
            XCTAssertEqual(frame.minY, rows[row], accuracy: 1, id)
            XCTAssertEqual(frame.width, cup.frame.width, accuracy: 1, id)
            XCTAssertEqual(frame.height, cup.frame.height, accuracy: 1, id)
        }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "board-landscape"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testRelaunchAndEditingOneLabelKeepAllCellFrames() {
        let app = launchBoard()
        XCTAssertTrue(app.buttons["tile-cup"].waitForExistence(timeout: 10))
        let ids = ["cup", "stop", "no", "open", "park", "go", "more", "help", "ball", "book"]
        let before = ids.map { app.buttons["tile-\($0)"].frame }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tile-cup"].waitForExistence(timeout: 10))
        XCTAssertEqual(ids.map { app.buttons["tile-\($0)"].frame }, before)
        app.terminate()
        app.launchArguments = ["--silent-speech-test", "--changed-cup"]
        app.launch()
        XCTAssertTrue(app.buttons["tile-cup"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["tile-cup"].label, "A different cup")
        XCTAssertEqual(ids.map { app.buttons["tile-\($0)"].frame }, before)
    }

    @MainActor
    func testEveryTileHasVoiceOverLabelAndTapFeedback() {
        let app = launchBoard()
        let cup = app.buttons["tile-cup"]
        XCTAssertTrue(cup.waitForExistence(timeout: 10))
        for (id, label) in [("cup", "Cup"), ("stop", "Stop"), ("no", "No"), ("open", "Open"),
                            ("park", "Park"), ("go", "Go"), ("more", "More"), ("help", "Help"),
                            ("ball", "Ball"), ("book", "Book")] {
            XCTAssertEqual(app.buttons["tile-\(id)"].label, label)
        }
        cup.tap()
        XCTAssertTrue(cup.isSelected)
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == false"), object: cup)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 3), .completed)
        // A second intentional tap remains available immediately, without a long press.
        cup.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)).tap()
        XCTAssertTrue(cup.isSelected)
    }

    @MainActor
    func testRotationsKeepLandscapeGridGeometry() async throws {
        let app = launchBoard()
        XCTAssertTrue(app.buttons["tile-cup"].waitForExistence(timeout: 10))
        let before = try await settledBoardFrames(app)
        let beforeBounds = before.values.reduce(CGRect.null) { $0.union($1) }
        for orientation: UIDeviceOrientation in [.portrait, .landscapeRight, .portraitUpsideDown, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let after = try await settledBoardFrames(app)
            let bounds = after.values.reduce(CGRect.null) { $0.union($1) }
            XCTAssertGreaterThan(bounds.width, bounds.height)
            XCTAssertEqual(bounds.width / bounds.height, beforeBounds.width / beforeBounds.height, accuracy: 0.01)
            // iPadOS may letterbox the landscape scene. Compare within the board, not screen pixels.
            for (id, initialFrame) in before {
                let initial = normalized(initialFrame, within: beforeBounds)
                let current = normalized(after[id]!, within: bounds)
                XCTAssertEqual(current.minX, initial.minX, accuracy: 0.002, id)
                XCTAssertEqual(current.minY, initial.minY, accuracy: 0.002, id)
                XCTAssertEqual(current.width, initial.width, accuracy: 0.002, id)
                XCTAssertEqual(current.height, initial.height, accuracy: 0.002, id)
            }
        }
    }

    @MainActor
    private func settledBoardFrames(_ app: XCUIApplication) async throws -> [String: CGRect] {
        var previous = boardFrames(app)
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(200))
            let current = boardFrames(app)
            if current == previous { return current }
            previous = current
        }
        XCTFail("The system rotation did not settle")
        return previous
    }

    @MainActor
    private func boardFrames(_ app: XCUIApplication) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        for id in ["cup", "stop", "no", "open", "park", "go", "more", "help", "ball", "book"] {
            frames[id] = app.buttons["tile-\(id)"].frame
        }
        for id in ["0-2", "1-1", "1-3", "2-2", "2-4"] {
            frames[id] = app.otherElements["empty-\(id)"].frame
        }
        return frames
    }

    private func normalized(_ frame: CGRect, within bounds: CGRect) -> CGRect {
        CGRect(x: (frame.minX - bounds.minX) / bounds.width,
               y: (frame.minY - bounds.minY) / bounds.height,
               width: frame.width / bounds.width, height: frame.height / bounds.height)
    }

    @MainActor
    private func launchBoard() -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--silent-speech-test"]
        app.launch()
        return app
    }
}
