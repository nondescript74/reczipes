//
//  Reczipes2UITests.swift
//  Reczipes2UITests
//
//  Created by Zahirudeen Premji on 12/4/25.
//

import XCTest
import OSLog

final class Reczipes2UITests: XCTestCase {
    
    private let logger = Logger(subsystem: "com.reczipes.uitests", category: "general")

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
    func testExample() throws {
        logger.info("🧪 Starting testExample")
        
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        
        logger.info("🚀 Launching app")
        app.launch()
        
        // Wait for app to reach foreground
        let launched = app.wait(for: .runningForeground, timeout: 5)
        XCTAssertTrue(launched, "App should reach foreground")
        logger.info("✅ App launched and in foreground")
        
        // Give UI time to settle
        sleep(1)
        
        // Verify main UI elements are present
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar should exist")
        logger.info("✅ Tab bar found")

        // The app declares 6 tabs in MainTabView (Recipes, Books, Meals,
        // Cooking, Extract, Settings). On iPhone, iOS surfaces only the
        // first 4 as direct tab-bar buttons and rolls the rest under a
        // "More" menu, so we only assert on the always-visible set here.
        // Extract and Settings are reachable via "More" and shouldn't be
        // asserted as top-level tab buttons.
        let alwaysVisibleTabs = ["Recipes", "Books", "Meals", "Cooking"]
        for tabName in alwaysVisibleTabs {
            let tab = app.tabBars.buttons[tabName]
            XCTAssertTrue(tab.exists, "\(tabName) tab should exist as a top-level tab")
        }

        logger.info("✅ All always-visible tabs found")
        logger.info("✅ testExample completed successfully")
    }

    @MainActor
    func testLaunchPerformance() throws {
        logger.info("⚡ Starting testLaunchPerformance")
        
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["UI_TESTING"]
            app.launch()
        }
        
        logger.info("✅ testLaunchPerformance completed")
    }
}
