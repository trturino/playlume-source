// Run on macOS:
// xcrun swiftc Hololink/StereoVideoColorProfile.swift Tests/StereoVideoColorTests.swift -o /tmp/stereo-color-tests
// /tmp/stereo-color-tests
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import CoreVideo
import Foundation

@main
struct StereoVideoColorTests {
    static func buffer(_ format: OSType) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, format,
                                        [kCVPixelBufferIOSurfacePropertiesKey: [:],
                                         kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &buffer)
        precondition(result == kCVReturnSuccess)
        return buffer!
    }

    static func value(_ key: CFString, from buffer: CVPixelBuffer) -> CFTypeRef? {
        CVBufferCopyAttachment(buffer, key, nil)
    }

    static func main() {
        let context = CIContext(options: [
            .workingColorSpace: StereoVideoColorProfile.workingColorSpace,
            .workingFormat: CIFormat.RGBAh.rawValue,
            .cacheIntermediates: false,
        ])
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let metadata: NSDictionary = [kCVImageBufferContentLightLevelInfoKey as String: Data([0x03, 0xe8, 0x01, 0x90])]

        for profile in [StereoVideoColorProfile.pq, .hlg, .sdr] {
            let source = buffer(profile.pixelFormat)
            profile.applyAttachments(to: source, metadata: metadata)
            precondition(StereoVideoColorProfile(source: source) == profile)
            precondition(CFEqual(value(kCVImageBufferTransferFunctionKey, from: source), profile.transferFunction))

            // Colored highlights above reference white must survive source
            // decoding, eye compositing, and HDR output encoding.
            let components: [CGFloat] = profile.isHDR ? [4, 2, 0.25] : [0.5, 0.3, 0.1]
            let image = CIImage(color: CIColor(red: components[0], green: components[1], blue: components[2], alpha: 1,
                                              colorSpace: StereoVideoColorProfile.workingColorSpace)!)
                .cropped(to: extent)
            context.render(image, to: source, bounds: extent, colorSpace: profile.colorSpace)
            let decoded = CIImage(cvPixelBuffer: source)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = decoded
            blend.backgroundImage = decoded
            blend.maskImage = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: extent)

            var eyes: [CVPixelBuffer] = []
            for _ in 0..<2 {
                let eye = buffer(profile.pixelFormat)
                let copiedMetadata = profile.metadata(from: source)
                profile.applyAttachments(to: eye, metadata: copiedMetadata)
                context.render(blend.outputImage!, to: eye, bounds: extent, colorSpace: profile.colorSpace)
                precondition(StereoVideoColorProfile(source: eye) == profile)
                if profile.isHDR {
                    precondition(profile.pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
                    precondition(CFEqual(value(kCVImageBufferContentLightLevelInfoKey, from: eye),
                                         value(kCVImageBufferContentLightLevelInfoKey, from: source)))
                }

                var rgba = [Float](repeating: 0, count: 4)
                rgba.withUnsafeMutableBytes {
                    context.render(CIImage(cvPixelBuffer: eye), toBitmap: $0.baseAddress!, rowBytes: 16,
                                   bounds: CGRect(x: 8, y: 8, width: 1, height: 1), format: .RGBAf,
                                   colorSpace: StereoVideoColorProfile.workingColorSpace)
                }
                for channel in 0..<3 {
                    precondition(abs(rgba[channel] - Float(components[channel])) < 0.15,
                                 "\(profile) lost color/headroom: \(rgba)")
                }

                // A recycled eye buffer must not retain obsolete HDR metadata.
                profile.applyAttachments(to: eye, metadata: NSDictionary())
                precondition(value(kCVImageBufferContentLightLevelInfoKey, from: eye) == nil)
                eyes.append(eye)
            }

            let taggedBuffers = [
                CMTaggedBuffer(tags: [.videoLayerID(0), .stereoView(.leftEye), .mediaType(.video)], pixelBuffer: eyes[0]),
                CMTaggedBuffer(tags: [.videoLayerID(1), .stereoView(.rightEye), .mediaType(.video)], pixelBuffer: eyes[1]),
            ]
            let format = CMFormatDescription(taggedBuffers: taggedBuffers)
            let sample = CMSampleBuffer(taggedBuffers: taggedBuffers, presentationTimeStamp: .zero,
                                        duration: CMTime(value: 1, timescale: 90), formatDescription: format)
            precondition(sample.isValid)
        }

        let untagged = buffer(kCVPixelFormatType_32BGRA)
        precondition(StereoVideoColorProfile(source: untagged) == .sdr)
        let recycled = buffer(kCVPixelFormatType_32BGRA)
        StereoVideoColorProfile.pq.applyAttachments(to: recycled, metadata: metadata)
        StereoVideoColorProfile.sdr.applyAttachments(to: recycled, metadata: metadata)
        precondition(StereoVideoColorProfile(source: recycled) == .sdr)
        precondition(value(kCVImageBufferContentLightLevelInfoKey, from: recycled) == nil)
        print("Passed PQ, HLG, SDR, both-eye luminance, metadata, and recycled-buffer checks")
    }
}
