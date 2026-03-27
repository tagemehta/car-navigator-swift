//
//  MetaGlassesEnvironment.swift
//  thing-finder
//
//  Shared container for WearablesViewModel and StreamSessionViewModel so both
//  SwiftUI views and UIKit-based FrameProviders can access the same instances.
//

import MWDATCore
import SwiftUI

@MainActor
final class MetaGlassesEnvironment: ObservableObject {
  static let shared = MetaGlassesEnvironment()

  let wearablesViewModel: WearablesViewModel
  let streamSessionViewModel: StreamSessionViewModel

  private init() {
    self.wearablesViewModel = WearablesViewModel(wearables: Wearables.shared)
    self.streamSessionViewModel = StreamSessionViewModel(wearables: Wearables.shared)
  }
}
