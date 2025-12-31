import Foundation
import Combine

/// Protocol defining FPS calculation functionality
protocol FPSCalculator {
    /// Current calculated FPS value
    var currentFPS: Double { get }
    
    /// Publisher for the currentFPS value
    var fpsPublisher: AnyPublisher<Double, Never> { get }
    
    /// Updates the FPS calculation with a new frame
    func updateFPSCalculation()
    
    /// Resets the FPS calculation state
    func reset()
}


/// Manages FPS (Frames Per Second) calculation for camera feeds
class FPSManager: FPSCalculator, ObservableObject {
    /// Array of timestamps for frames processed within the last second
    private var frameTimes: [Date] = []
    
    /// Current calculated FPS value
    @Published var currentFPS: Double = 0.0
    
    /// Publisher for the currentFPS value
    var fpsPublisher: AnyPublisher<Double, Never> {
        $currentFPS.eraseToAnyPublisher()
    }
    
    /// Updates the FPS calculation with a new frame
    func updateFPSCalculation() {
        let now = Date()
        frameTimes.append(now)
        // Remove timestamps older than 1 second
        frameTimes = frameTimes.filter { now.timeIntervalSince($0) <= 1.0 }
        calculateAndPublishFPS()
    }
    
    /// Calculates and publishes the current FPS value
    private func calculateAndPublishFPS() {
        guard frameTimes.count >= 2 else { return }
        
        let timeInterval = frameTimes.last!.timeIntervalSince(frameTimes.first!)
        if timeInterval > 0 {
            let fps = Double(frameTimes.count - 1) / timeInterval
            DispatchQueue.main.async {
                self.currentFPS = min(fps, 60.0)  // Cap at 60 FPS which is typical for iOS
            }
        }
    }
    
    /// Resets the FPS calculation state
    func reset() {
        frameTimes.removeAll()
        DispatchQueue.main.async {
            self.currentFPS = 0.0
        }
    }
}
