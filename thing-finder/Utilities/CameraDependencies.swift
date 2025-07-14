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
    let imageUtils: ImageUtilities
}

