//
//  mac_promptUITests.swift
//  mac-promptUITests
//
//  Launches the real app. Read-only: the app opens the user's own library, so these
//  tests must not create, change or delete scripts.

import XCTest

final class mac_promptUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLibraryWindowOpens() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["New Script"].waitForExistence(timeout: 10))
    }
}
