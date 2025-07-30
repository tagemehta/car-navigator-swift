//
//  CameraDependencies.swift
//  thing-finder
//
//  Created by Sam Mehta on 6/25/25.


import CoreML
import Vision

/// Groups all dependencies required by CameraViewModel
struct CameraDependencies {
    let targetClasses: [String]
    let targetTextDescription: String
    let settings: Settings
    let detectionManager: DetectionManager
    let imageUtils: ImageUtilities
    let fpsManager: FPSCalculator
}

// MARK: - Factory

extension CameraDependencies {
    /// Creates a default set of dependencies
    static func makeDefault(
        targetClasses: [String],
        targetTextDescription: String,
        settings: Settings = Settings()
    ) -> CameraDependencies {
        let model = try! VNCoreMLModel(for: yolo11n(configuration: .init()).model)
      model.featureProvider = ThresholdProvider(iouThreshold: 0.45, confidenceThreshold: 0.25)
        let detectionManager = DetectionManager(
            model: model
        )
        
        return CameraDependencies(
            targetClasses: targetClasses,
            targetTextDescription: targetTextDescription,
            settings: settings,
            detectionManager: detectionManager,
            imageUtils: ImageUtilities(),
            fpsManager: FPSManager()
        )
    }
}
