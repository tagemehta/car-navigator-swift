//
//  CompassHeading.swift
//  thing-finder
//
//  Created by Beckett Roberge on 7/29/25.
//

import Foundation
import Combine
import CoreLocation
import CoreMotion

//IDK what any of this code is doing, It is setting up the compass value
//the totorial i fallowed is https://www.youtube.com/watch?v=rDGwQRr0K0U

class CompassHeading: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = CompassHeading()
    var objectWillChange = PassthroughSubject<Void, Never>()
    var degrees: Double = .zero {
        didSet {
            objectWillChange.send()
        }
    }
    private let locationManager: CLLocationManager
    
    override init(){
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
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        self.degrees = 360.0 - newHeading.magneticHeading
    }

}
