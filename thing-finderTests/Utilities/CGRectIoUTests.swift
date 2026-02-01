//  CGRectIoUTests.swift
//  thing-finderTests
//
//  Unit tests for CGRect IoU (Intersection over Union) extension.

import XCTest

@testable import thing_finder

final class CGRectIoUTests: XCTestCase {

  // MARK: - Identical Rects

  func test_iou_identicalRects() {
    let rect = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)

    let iou = rect.iou(with: rect)

    XCTAssertEqual(iou, 1.0, accuracy: 0.001)
  }

  // MARK: - No Overlap

  func test_iou_noOverlap() {
    let rect1 = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)
    let rect2 = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)

    let iou = rect1.iou(with: rect2)

    XCTAssertEqual(iou, 0.0)
  }

  func test_iou_adjacentRects_noOverlap() {
    let rect1 = CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5)
    let rect2 = CGRect(x: 0.5, y: 0.0, width: 0.5, height: 0.5)

    let iou = rect1.iou(with: rect2)

    XCTAssertEqual(iou, 0.0)
  }

  // MARK: - Partial Overlap

  func test_iou_partialOverlap() {
    // Two 0.4x0.4 rects with 0.2x0.4 overlap
    // Intersection area = 0.2 * 0.4 = 0.08
    // Union area = 0.16 + 0.16 - 0.08 = 0.24
    // IoU = 0.08 / 0.24 = 0.333...
    let rect1 = CGRect(x: 0.0, y: 0.0, width: 0.4, height: 0.4)
    let rect2 = CGRect(x: 0.2, y: 0.0, width: 0.4, height: 0.4)

    let iou = rect1.iou(with: rect2)

    XCTAssertEqual(iou, 1.0 / 3.0, accuracy: 0.001)
  }

  func test_iou_50percentOverlap() {
    // rect1: 0.0-0.4 x 0.0-0.4 (area = 0.16)
    // rect2: 0.2-0.6 x 0.0-0.4 (area = 0.16)
    // Intersection: 0.2-0.4 x 0.0-0.4 = 0.2 * 0.4 = 0.08
    // Union: 0.16 + 0.16 - 0.08 = 0.24
    // IoU = 0.08 / 0.24 ≈ 0.333
    let rect1 = CGRect(x: 0.0, y: 0.0, width: 0.4, height: 0.4)
    let rect2 = CGRect(x: 0.2, y: 0.0, width: 0.4, height: 0.4)

    let iou = rect1.iou(with: rect2)

    XCTAssertEqual(iou, 0.333, accuracy: 0.01)
  }

  // MARK: - Containment

  func test_iou_oneContainsOther() {
    let outer = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
    let inner = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

    let iou = outer.iou(with: inner)

    // Intersection = inner area = 0.25
    // Union = outer area = 1.0
    // IoU = 0.25 / 1.0 = 0.25
    XCTAssertEqual(iou, 0.25, accuracy: 0.001)
  }

  // MARK: - Edge Cases

  func test_iou_zeroSizeRect() {
    let rect1 = CGRect(x: 0.5, y: 0.5, width: 0.0, height: 0.0)
    let rect2 = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)

    let iou = rect1.iou(with: rect2)

    XCTAssertEqual(iou, 0.0)
  }

  func test_iou_bothZeroSize() {
    let rect1 = CGRect(x: 0.5, y: 0.5, width: 0.0, height: 0.0)
    let rect2 = CGRect(x: 0.5, y: 0.5, width: 0.0, height: 0.0)

    let iou = rect1.iou(with: rect2)

    XCTAssertEqual(iou, 0.0)
  }

  func test_iou_isCommutative() {
    let rect1 = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4)
    let rect2 = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.3)

    let iou1 = rect1.iou(with: rect2)
    let iou2 = rect2.iou(with: rect1)

    XCTAssertEqual(iou1, iou2, accuracy: 0.0001)
  }

  // MARK: - Normalized Coordinates (0-1 range)

  func test_iou_normalizedCoordinates() {
    // Typical bounding boxes in normalized image coordinates
    let detection1 = CGRect(x: 0.3, y: 0.4, width: 0.2, height: 0.3)
    let detection2 = CGRect(x: 0.35, y: 0.45, width: 0.2, height: 0.3)

    let iou = detection1.iou(with: detection2)

    // Should have significant overlap
    XCTAssertGreaterThan(iou, 0.3)
    XCTAssertLessThan(iou, 0.7)
  }
}
