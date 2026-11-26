// xcrun swiftc Hololink/StereoDepthSettings.swift Tests/StereoDepthSettingsTests.swift -o /tmp/stereo-settings-tests
import Foundation

@main
struct StereoDepthSettingsTests {
    static func main() throws {
        // Saved device payload before replacing the tuning controls.
        let deviceJSON = #"{"configuration":{"depthContrast":2.0700000000000003,"depthBlurRadius":1.49,"foregroundSharpnessIntensity":0.9,"foregroundShift":0.19,"backgroundShift":0.21,"depthClampMax":0.95,"depthRefreshInterval":2,"foregroundSharpnessRadius":1.1,"maximumOutputWidth":1184,"invertDepth":false,"depthGamma":0.73,"depthClampMin":0.21,"strength":0.05,"depthBrightness":-0.05},"renderingMode":"performance"}"#
        let device = try JSONSerialization.jsonObject(with: Data(deviceJSON.utf8)) as! [String: Any]
        let expected = device["configuration"] as! [String: Any]
        let baseline = StereoDepthConfiguration.defaultValue
        let actual = try JSONSerialization.jsonObject(with: JSONEncoder().encode(baseline)) as! [String: Any]
        precondition(actual.keys.count == expected.keys.count)
        for (key, value) in expected {
            let expectedNumber = value as! NSNumber
            let actualNumber = actual[key] as! NSNumber
            precondition(abs(expectedNumber.doubleValue - actualNumber.doubleValue) < 1e-12, key)
        }
        precondition(baseline.clamped() == baseline)
        precondition(StereoDepthModel.defaultValue.rawValue == "DepthAnythingV2SmallF16P6")
        precondition(StereoDepthRenderingMode.defaultValue == .performance)
        precondition(StereoDepthRenderingMode.allCases == [.quality, .performance])
        precondition(StereoDepthRenderingMode.restored(from: deviceJSON) == .performance)

        for mode in StereoDepthRenderingMode.allCases {
            let legacy = #"{"configuration":{"strength":0.2},"profiles":{"legacy":{}},"renderingMode":"MODE"}"#
                .replacingOccurrences(of: "MODE", with: mode.rawValue)
            precondition(StereoDepthRenderingMode.restored(from: legacy) == mode)
            let encoded = try JSONEncoder().encode(StereoDepthPersistencePayload(renderingMode: mode))
            let json = String(data: encoded, encoding: .utf8)!
            let persisted = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            precondition(Set(persisted.keys) == ["renderingMode"])
            precondition(StereoDepthRenderingMode.restored(from: json) == mode)
            precondition(StereoDepthConfiguration.defaultValue == baseline)
        }

        for invalid in ["", "invalid", "{}", #"{"renderingMode":"unknown"}"#] {
            precondition(StereoDepthRenderingMode.restored(from: invalid) == .performance)
        }
        print("Passed device baseline, legacy migration, mode persistence, and first-launch defaults checks")
    }
}
