//  SettingsMigrationTests.swift
//  thing-finderTests
//
//  Upgrade path from allow_partial_nav to require_license_plate.

import XCTest

@testable import thing_finder

final class SettingsMigrationTests: XCTestCase {
  private var defaults: UserDefaults!
  private let suite = "SettingsMigrationTests"

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suite)
    defaults.removePersistentDomain(forName: suite)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    super.tearDown()
  }

  func test_legacyFalse_becomesRequireTrue() {
    defaults.set(false, forKey: "allow_partial_nav")
    Settings.migrateLegacyPartialNavigation(defaults: defaults)
    XCTAssertEqual(defaults.object(forKey: "require_license_plate") as? Bool, true)
    XCTAssertNil(defaults.object(forKey: "allow_partial_nav"))
  }

  func test_legacyTrue_becomesRequireFalse() {
    defaults.set(true, forKey: "allow_partial_nav")
    Settings.migrateLegacyPartialNavigation(defaults: defaults)
    XCTAssertEqual(defaults.object(forKey: "require_license_plate") as? Bool, false)
  }

  func test_noLegacyValue_leavesNewKeyUnset() {
    Settings.migrateLegacyPartialNavigation(defaults: defaults)
    XCTAssertNil(defaults.object(forKey: "require_license_plate"))
  }

  func test_existingNewValue_isNotOverwritten() {
    defaults.set(false, forKey: "require_license_plate")
    defaults.set(false, forKey: "allow_partial_nav")
    Settings.migrateLegacyPartialNavigation(defaults: defaults)
    XCTAssertEqual(defaults.object(forKey: "require_license_plate") as? Bool, false)
  }
}
