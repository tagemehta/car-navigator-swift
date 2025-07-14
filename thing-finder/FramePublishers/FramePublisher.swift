//
//  FramePublisher.swift
//  thing-finder
//
//  Created by Sam Mehta on 6/19/25.
//

import AVFoundation
import ARKit
import UIKit

protocol FrameProviderDelegate: AnyObject {

  /// Preferred callback for ARKit sources – gives full ARFrame
  func processFrame(
    _ provider: any FrameProvider,
    frame: ARFrame,
    buffer: CVPixelBuffer
  )
}

protocol FrameProvider: AnyObject {
  // Ready-made preview view to add to your hierarchy
  var previewView: UIView { get }
  /// Underlying ARSession if available (nil for non-ARKit providers)
  var session: ARSession? { get }

  var delegate: FrameProviderDelegate? { get set }

  /// The underlying capture source type (ARKit or AVFoundation).
  var sourceType: CaptureSourceType { get }
  
  /// Indicates whether the capture session is currently running.
  var isRunning: Bool { get }

  func start()
  func stop()
  /// Perform heavy capture/session wiring. Call once before `start()`.
  func setupSession()

}

enum CaptureSourceType {
  case arkit
}

// Default for providers that are not ARKit-based
extension FrameProvider {
  public var session: ARSession? { nil }
}

