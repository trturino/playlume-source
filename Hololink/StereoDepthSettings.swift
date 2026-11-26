import Foundation

// Stereo tuning captured from the Vision Pro. Both modes use this baseline;
// Performance can adapt processing cost under load.
enum StereoDepthModel: String, Hashable, Identifiable, Codable {
    case depthAnythingV2SmallF16 = "DepthAnythingV2SmallF16"
    case depthAnythingV2SmallF16P6 = "DepthAnythingV2SmallF16P6"
    case depthAnythingV2SmallF32 = "DepthAnythingV2SmallF32"
    case depthAnythingSmallF16 = "DepthAnythingSmallF16"
    case depthAnythingSmallF16P6 = "DepthAnythingSmallF16P6"

    static let defaultValue = Self.depthAnythingV2SmallF16P6
    var id: String { rawValue }
}

enum StereoDepthRenderingMode: String, CaseIterable, Hashable, Identifiable, Codable {
    case quality
    case performance

    static let defaultValue = Self.performance
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quality: return "Quality"
        case .performance: return "Performance"
        }
    }

    var detail: String {
        switch self {
        case .quality: return "Keeps stereo resolution and depth detail fixed."
        case .performance: return "Adapts stereo processing to keep motion smooth."
        }
    }

    static func restored(from json: String) -> Self {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(StereoDepthPersistencePayload.self, from: data) else {
            return .defaultValue
        }
        return payload.renderingMode ?? .defaultValue
    }
}

struct StereoDepthConfiguration: Hashable, Codable {
    static let defaultValue = StereoDepthConfiguration()

    var strength: Double = 0.05
    var foregroundShift: Double = 0.19
    var backgroundShift: Double = 0.21
    var depthContrast: Double = 2.07
    var depthBrightness: Double = -0.05
    var depthGamma: Double = 0.73
    var depthClampMin: Double = 0.21
    var depthClampMax: Double = 0.95
    var depthBlurRadius: Double = 1.49
    var foregroundSharpnessRadius: Double = 1.1
    var foregroundSharpnessIntensity: Double = 0.9
    var maximumOutputWidth: Double = 1184
    var depthRefreshInterval: Int = 2
    var invertDepth: Bool = false

    func clamped() -> StereoDepthConfiguration {
        var configuration = self
        configuration.strength = configuration.strength.clamped(to: 0.0...0.2)
        configuration.foregroundShift = configuration.foregroundShift.clamped(to: 0.0...2.0)
        configuration.backgroundShift = configuration.backgroundShift.clamped(to: 0.0...1.0)
        configuration.depthContrast = configuration.depthContrast.clamped(to: 0.5...8.0)
        configuration.depthBrightness = configuration.depthBrightness.clamped(to: -0.3...0.3)
        configuration.depthGamma = configuration.depthGamma.clamped(to: 0.2...2.0)
        configuration.depthClampMin = configuration.depthClampMin.clamped(to: 0.0...0.95)
        configuration.depthClampMax = configuration.depthClampMax.clamped(to: 0.05...1.0)
        if configuration.depthClampMin >= configuration.depthClampMax {
            configuration.depthClampMax = min(1.0, configuration.depthClampMin + 0.05)
        }
        configuration.depthBlurRadius = configuration.depthBlurRadius.clamped(to: 0.0...8.0)
        configuration.foregroundSharpnessRadius = configuration.foregroundSharpnessRadius.clamped(to: 0.0...3.0)
        configuration.foregroundSharpnessIntensity = configuration.foregroundSharpnessIntensity.clamped(to: 0.0...2.5)
        configuration.maximumOutputWidth = configuration.maximumOutputWidth.clamped(to: 640...1920)
        configuration.depthRefreshInterval = min(max(configuration.depthRefreshInterval, 1), 6)
        return configuration
    }
}

// Legacy payloads may also contain model-specific tuning. Only the chosen
// mode is restored now that the app supplies a single fixed stereo baseline.
struct StereoDepthPersistencePayload: Codable {
    var renderingMode: StereoDepthRenderingMode?
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
