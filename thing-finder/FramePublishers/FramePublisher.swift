//
//  FramePublisher.swift
//  thing-finder
//
//  Created by Sam Mehta on 6/19/25.
//

import AVFoundation
import UIKit

protocol FrameProviderDelegate: AnyObject {
  /// - buffer: BGRA pixel buffer of the live camera frame
  /// - depthAt: closure returning depth (metres) for a point in view-coords, or `nil`
  func processFrame(
    _ provider: any FrameProvider,
    buffer: CVPixelBuffer,
    depthAt: @escaping (CGPoint) -> Float?
  )
}

protocol FrameProvider: AnyObject {
  // Ready-made preview view to add to your hierarchy
  var previewView: UIView { get }

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
