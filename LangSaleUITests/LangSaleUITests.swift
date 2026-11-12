import XCTest

final class LangSaleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMainScreenShowsDirectionPickerAndStartButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        XCTAssertTrue(app.navigationBars["LangSale"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Start listening"].exists)
        XCTAssertTrue(app.staticTexts["Nothing translated yet."].exists)
    }

    @MainActor
    func testStartButtonIsEnabledWhenModelIsReady() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let start = app.buttons["Start listening"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.isEnabled)
    }
}
