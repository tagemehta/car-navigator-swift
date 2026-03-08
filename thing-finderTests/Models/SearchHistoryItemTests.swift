//  SearchHistoryItemTests.swift
//  thing-finderTests
//
//  Unit tests for SearchHistoryItem model and Codable conformance.

import XCTest

@testable import thing_finder

final class SearchHistoryItemTests: XCTestCase {

  // MARK: - Initialization

  func test_init_setsAllProperties() {
    let item = SearchHistoryItem(
      description: "Route 42 bus",
      mode: .uberFinder,
      isParatransitMode: true
    )

    XCTAssertEqual(item.description, "Route 42 bus")
    XCTAssertEqual(item.mode, .uberFinder)
    XCTAssertTrue(item.isParatransitMode)
    XCTAssertNotNil(item.id)
  }

  func test_init_generatesUniqueIds() {
    let item1 = SearchHistoryItem(description: "test", mode: .uberFinder, isParatransitMode: false)
    let item2 = SearchHistoryItem(description: "test", mode: .uberFinder, isParatransitMode: false)

    XCTAssertNotEqual(item1.id, item2.id)
  }

  // MARK: - Codable

  func test_encodeDecode_preservesAllFields() throws {
    let original = SearchHistoryItem(
      description: "blue MTA bus",
      mode: .uberFinder,
      isParatransitMode: true
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(SearchHistoryItem.self, from: data)

    XCTAssertEqual(decoded.id, original.id)
    XCTAssertEqual(decoded.description, original.description)
    XCTAssertEqual(decoded.mode, original.mode)
    XCTAssertEqual(decoded.isParatransitMode, original.isParatransitMode)
  }

  func test_encodeDecode_objectFinderMode() throws {
    let original = SearchHistoryItem(
      description: "red backpack",
      mode: .objectFinder,
      isParatransitMode: false
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(SearchHistoryItem.self, from: data)

    XCTAssertEqual(decoded.mode, .objectFinder)
    XCTAssertFalse(decoded.isParatransitMode)
  }

  func test_encodeDecodeArray_preservesOrder() throws {
    let items = [
      SearchHistoryItem(description: "Route 1", mode: .uberFinder, isParatransitMode: true),
      SearchHistoryItem(description: "Route 2", mode: .uberFinder, isParatransitMode: false),
      SearchHistoryItem(description: "laptop", mode: .objectFinder, isParatransitMode: false),
    ]

    let encoder = JSONEncoder()
    let data = try encoder.encode(items)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode([SearchHistoryItem].self, from: data)

    XCTAssertEqual(decoded.count, 3)
    XCTAssertEqual(decoded[0].description, "Route 1")
    XCTAssertEqual(decoded[1].description, "Route 2")
    XCTAssertEqual(decoded[2].description, "laptop")
    XCTAssertTrue(decoded[0].isParatransitMode)
    XCTAssertFalse(decoded[1].isParatransitMode)
    XCTAssertEqual(decoded[2].mode, .objectFinder)
  }

  // MARK: - SearchMode Codable

  func test_searchMode_encodeDecode_uberFinder() throws {
    let mode = SearchMode.uberFinder

    let encoder = JSONEncoder()
    let data = try encoder.encode(mode)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(SearchMode.self, from: data)

    XCTAssertEqual(decoded, .uberFinder)
  }

  func test_searchMode_encodeDecode_objectFinder() throws {
    let mode = SearchMode.objectFinder

    let encoder = JSONEncoder()
    let data = try encoder.encode(mode)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(SearchMode.self, from: data)

    XCTAssertEqual(decoded, .objectFinder)
  }
}
