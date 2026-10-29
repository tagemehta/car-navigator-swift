import Foundation

/// Centralized feature flags for controlling beta and experimental features
public struct FeatureFlags {

  /// Controls whether Meta Ray-Ban glasses integration is available
  /// Set to false to hide Meta glasses features (e.g. to ship a build without them)
  public static let metaGlassesEnabled: Bool = {
    #if DEBUG
      return true
    #else
      return true  // Shipping in release builds
    #endif
  }()
}
