//
//  NuageUITests.swift
//  NuageUITests
//
//  Created by Laurin Brandner on 14.11.2026.
//

import XCTest

final class NuageUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Clicking anywhere on the search field in the window toolbar should focus it.
    /// Clicks near the edges matter: the centered toolbar item has been laid out narrower than the field it draws,
    /// so only clicks in the middle reached the field.
    /// Requires being logged in, otherwise the app shows the login screen without a toolbar.
    @MainActor
    func testClickingSearchFieldFocusesIt() throws {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        let searchField = window.toolbars.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field not found in the toolbar. Is the app logged in?")

        for offset in [0.1, 0.5, 0.9] {
            // Click the content area first so the search field loses focus
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).click()
            searchField.coordinate(withNormalizedOffset: CGVector(dx: offset, dy: 0.5)).click()

            let hasFocus = searchField.value(forKey: "hasKeyboardFocus") as? Bool ?? false
            XCTAssertTrue(hasFocus, "Clicking the search field at \(Int(offset * 100))% of its width didn't focus it")
        }
    }

    /// Clicking the clear button of the search field should clear the search.
    /// The button sits at the trailing edge of the field, which the centered toolbar item doesn't cover.
    @MainActor
    func testClearButtonClearsSearchField() throws {
        let app = XCUIApplication()
        app.launch()

        let searchField = app.windows.firstMatch.toolbars.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field not found in the toolbar. Is the app logged in?")

        searchField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        searchField.typeText("nuage")
        XCTAssertEqual(searchField.value as? String, "nuage")

        let clearButton = searchField.buttons.element(boundBy: searchField.buttons.count - 1)
        XCTAssertTrue(clearButton.exists)
        clearButton.click()

        XCTAssertEqual(searchField.value as? String ?? "", "")
    }
}
