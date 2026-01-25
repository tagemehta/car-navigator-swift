//  ImageUtilitiesTests.swift
//  thing-finderTests
//
//  Unit tests for ImageUtilities.

import CoreGraphics
import Vision
import XCTest

@testable import thing_finder

final class ImageUtilitiesTests: XCTestCase {

  let utils = ImageUtilities.shared

  // MARK: - cgOrientation

  func test_cgOrientation_portrait_returnsRight() {
    XCTAssertEqual(utils.cgOrientation(for: .portrait), .right)
  }

  func test_cgOrientation_portraitUpsideDown_returnsLeft() {
    XCTAssertEqual(utils.cgOrientation(for: .portraitUpsideDown), .left)
  }

  func test_cgOrientation_landscapeLeft_returnsDown() {
    XCTAssertEqual(utils.cgOrientation(for: .landscapeLeft), .down)
  }

  func test_cgOrientation_landscapeRight_returnsUp() {
    XCTAssertEqual(utils.cgOrientation(for: .landscapeRight), .up)
  }

  func test_cgOrientation_unknown_returnsRight() {
    XCTAssertEqual(utils.cgOrientation(for: .unknown), .right)
  }

  // MARK: - inverseRotation (Normalized)

  func test_inverseRotation_up_returnsUnchanged() {
    let rect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    let result = utils.inverseRotation(rect, for: .up)
    XCTAssertEqual(result, rect)
  }

  func test_inverseRotation_down_rotates180() {
    let rect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    let result = utils.inverseRotation(rect, for: .down)

    XCTAssertEqual(result.origin.x, 1 - rect.maxX, accuracy: 1e-6)
    XCTAssertEqual(result.origin.y, 1 - rect.maxY, accuracy: 1e-6)
    XCTAssertEqual(result.width, rect.width, accuracy: 1e-6)
    XCTAssertEqual(result.height, rect.height, accuracy: 1e-6)
  }

  func test_inverseRotation_left_rotates90CCW() {
    let rect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    let result = utils.inverseRotation(rect, for: .left)

    XCTAssertEqual(result.origin.x, rect.minY, accuracy: 1e-6)
    XCTAssertEqual(result.origin.y, 1 - rect.maxX, accuracy: 1e-6)
    XCTAssertEqual(result.width, rect.height, accuracy: 1e-6)
    XCTAssertEqual(result.height, rect.width, accuracy: 1e-6)
  }

  func test_inverseRotation_right_rotates90CW() {
    let rect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    let result = utils.inverseRotation(rect, for: .right)

    XCTAssertEqual(result.origin.x, 1 - rect.maxY, accuracy: 1e-6)
    XCTAssertEqual(result.origin.y, rect.minX, accuracy: 1e-6)
    XCTAssertEqual(result.width, rect.height, accuracy: 1e-6)
    XCTAssertEqual(result.height, rect.width, accuracy: 1e-6)
  }

  // MARK: - inverseOrientation

  func test_inverseOrientation_up_returnsDown() {
    XCTAssertEqual(utils.inverseOrientation(.up), .down)
  }

  func test_inverseOrientation_down_returnsUp() {
    XCTAssertEqual(utils.inverseOrientation(.down), .up)
  }

  func test_inverseOrientation_left_returnsRight() {
    XCTAssertEqual(utils.inverseOrientation(.left), .right)
  }

  func test_inverseOrientation_right_returnsLeft() {
    XCTAssertEqual(utils.inverseOrientation(.right), .left)
  }

  // MARK: - Blur Score

  func test_blurScore_returnsValueInRange() {
    // Create a simple solid color test image
    let size = CGSize(width: 100, height: 100)
    UIGraphicsBeginImageContext(size)
    let context = UIGraphicsGetCurrentContext()!
    context.setFillColor(UIColor.white.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    let image = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()

    let score = utils.blurScore(from: image)

    XCTAssertNotNil(score)
    XCTAssertGreaterThanOrEqual(score!, 0.0)
    XCTAssertLessThanOrEqual(score!, 1.0)
  }

  func test_blurScore_nilImage_returnsNil() {
    // Create an image without a CGImage backing
    let emptyImage = UIImage()
    let score = utils.blurScore(from: emptyImage)

    XCTAssertNil(score)
  }
}
