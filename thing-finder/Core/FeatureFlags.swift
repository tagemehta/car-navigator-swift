import Foundation

/// Centralized feature flags for controlling beta and experimental features
public struct FeatureFlags {

  /// Controls whether Meta Ray-Ban glasses integration is available
  /// Set to false to hide Meta glasses features in production builds
  public static let metaGlassesEnabled: Bool = {
    #if DEBUG
      return true  // Always enabled in debug builds for testing
    #else
      return false  // Disabled in release builds (beta feature)
    #endif
  }()
}
