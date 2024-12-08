//
//  Helpers.swift
//  YOLO
//
//  Created by Sam Mehta on 12/7/24.
//  Copyright © 2024 Ultralytics. All rights reserved.
//
import CoreGraphics

extension ViewController {
    func intersectionOverUnion(rect1: CGRect, rect2: CGRect) -> CGFloat {
        // Calculate the intersection rectangle
        let intersection = rect1.intersection(rect2)
        
        // Check if there's no intersection
        if intersection.isNull {
            return 0.0
        }
        
        // Calculate the areas of the rectangles
        let intersectionArea = intersection.width * intersection.height
        let rect1Area = rect1.width * rect1.height
        let rect2Area = rect2.width * rect2.height
        
        // Calculate the union area
        let unionArea = rect1Area + rect2Area - intersectionArea
        
        // Calculate IoU
        return intersectionArea / unionArea
    }
    
    

}


