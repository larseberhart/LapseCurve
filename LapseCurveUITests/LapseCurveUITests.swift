//
//  LapseCurveUITests.swift
//  LapseCurveUITests
//
//  Created by Lars EBERHART on 14.10.26.
//

import AppKit
import XCTest

final class LapseCurveUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testEditorShellLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.buttons["choose-folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["execute-interpolations"].exists)
        XCTAssertFalse(app.buttons["execute-interpolations"].isEnabled)
        XCTAssertFalse(app.staticTexts["PREVIEW"].exists)
        XCTAssertTrue(app.buttons["reload-metadata"].exists)
        XCTAssertFalse(app.buttons["reload-metadata"].isEnabled)
        XCTAssertTrue(app.buttons["undo"].exists)
        XCTAssertFalse(app.buttons["undo"].isEnabled)
    }

    @MainActor
    func testDevelopmentInspectorHasNoCorrectionControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.radioButtons["Development"].click()
        XCTAssertTrue(app.staticTexts["DEVELOPMENT"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["capture-exposure-enabled"].exists)
        XCTAssertFalse(app.sliders["capture-exposure-strength"].exists)
        XCTAssertFalse(app.sliders["exposure-override-slider"].exists)
        XCTAssertFalse(app.buttons["clear-exposure-override"].exists)
    }

    @MainActor
    func testSegmentCurvePickerEditsAndUndoes() throws {
        let app = launchSequence()
        let curve = app.popUpButtons["interpolation-curve-0"]
        expectValue(curve, "Default")
        let graph = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier != %@", "parameter-graph-", "parameter-graph-tooltip"
        )).firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["keyframe-read-only"].exists)
        graph.hover()
        wait(for: NSPredicate(format: "label CONTAINS %@", "Frame "), on: graph)
        XCTAssertTrue(app.descendants(matching: .any)["keyframe-read-only"].exists)
        changeCurve("Hold", in: app)
        wait(for: NSPredicate(format: "label ENDSWITH %@", "hold"), on: graph)
        app.buttons["undo"].click()
        expectValue(curve, "Default")
        app.buttons["redo"].click()
        expectValue(curve, "Hold")
        changeCurve("Smoothstep", in: app)
        wait(for: NSPredicate(format: "label ENDSWITH %@", "smoothstep"), on: graph)
        changeCurve("Default", in: app)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Interval graphs and curve selection"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testRepeatedExecutionKeepsResultsVisible() throws {
        let app = launchSequence()
        executeAndExpect(6, in: app)
        app.buttons["Done"].click()
        changeCurve("Hold", in: app)
        executeAndExpect(3, in: app)
    }

    @MainActor
    func testWorkingFolderChooserCanBeCancelled() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.buttons["choose-folder"].click()
        let panel = app.sheets["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.buttons["Cancel"].click()
        XCTAssertFalse(app.buttons["execute-interpolations"].isEnabled)
    }

    @MainActor
    func testLaunchPerformance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }

    @MainActor
    private func launchSequence() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-sequence"]
        app.launch()
        XCTAssertTrue(app.popUpButtons["interpolation-curve-0"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func changeCurve(_ value: String, in app: XCUIApplication) {
        let curve = app.popUpButtons["interpolation-curve-0"]
        curve.click()
        app.menuItems[value].click()
        expectValue(curve, value)
    }

    @MainActor
    private func executeAndExpect(_ count: Int, in app: XCUIApplication) {
        let execute = app.buttons["execute-interpolations"]
        wait(for: NSPredicate(format: "enabled == true"), on: execute)
        execute.click()
        let confirm = app.buttons["confirm-execute-interpolations"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.click()
        let results = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Results: \(count) updated")).firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 10))
    }

    @MainActor
    private func expectValue(_ element: XCUIElement, _ value: String) {
        wait(for: NSPredicate(format: "value == %@", value), on: element)
    }

    @MainActor
    private func wait(for predicate: NSPredicate, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }
}
