//
//  CompassHeading.swift
//  thing-finder
//
//  Created by Beckett Roberge on 7/29/25.
//

import Combine
import CoreLocation
import CoreMotion
import Foundation

// MARK: - CompassProvider Protocol

/// Protocol for compass heading access, enabling testability.
/// Production uses `CompassHeading.shared`; tests use `MockCompassProvider`.
public protocol CompassProvider: AnyObject {
  var degrees: Double { get }
}

//IDK what any of this code is doing, It is setting up the compass value
//the totorial i fallowed is https://www.youtube.com/watch?v=rDGwQRr0K0U

public class CompassHeading: NSObject, ObservableObject, CLLocationManagerDelegate, CompassProvider
{
  public static let shared = CompassHeading()
  public var objectWillChange = PassthroughSubject<Void, Never>()
  public var degrees: Double = .zero {
    didSet {
      objectWillChange.send()
    }
  }
  private let locationManager: CLLocationManager

  override init() {
    self.locationManager = CLLocationManager()
    super.init()

    self.locationManager.delegate = self
    self.setup()

  }

  private func setup() {
    self.locationManager.requestWhenInUseAuthorization()

    if CLLocationManager.headingAvailable() {
      self.locationManager.startUpdatingLocation()
      self.locationManager.startUpdatingHeading()
    }
  }

  // Updates compass value i think
  public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading)
  {
    self.degrees = 360.0 - newHeading.magneticHeading
  }

}
