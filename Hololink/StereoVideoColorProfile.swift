import CoreGraphics
import CoreVideo
import Foundation

/// Color encoding of the stereo eye buffers, independent of depth inference.
enum StereoVideoColorProfile: Equatable {
    case sdr, pq, hlg

    static let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
    static let sdrColorSpace = CGColorSpace(name: CGColorSpace.itur_709)!
    static let metadataKeys = [
        kCVImageBufferMasteringDisplayColorVolumeKey,
        kCVImageBufferContentLightLevelInfoKey,
        kCVImageBufferAmbientViewingEnvironmentKey,
    ]

    init(source: CVPixelBuffer) {
        let transfer = CVBufferCopyAttachment(source, kCVImageBufferTransferFunctionKey, nil)
        if let transfer, CFEqual(transfer, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ) {
            self = .pq
        } else if let transfer, CFEqual(transfer, kCVImageBufferTransferFunction_ITU_R_2100_HLG) {
            self = .hlg
        } else {
            self = .sdr
        }
    }

    var isHDR: Bool { self != .sdr }

    var pixelFormat: OSType {
        isHDR ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_32BGRA
    }

    var colorSpace: CGColorSpace {
        switch self {
        case .sdr: return Self.sdrColorSpace
        case .pq: return CGColorSpace(name: CGColorSpace.itur_2100_PQ)!
        case .hlg: return CGColorSpace(name: CGColorSpace.itur_2100_HLG)!
        }
    }

    var transferFunction: CFString {
        switch self {
        case .sdr: return kCVImageBufferTransferFunction_ITU_R_709_2
        case .pq: return kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
        case .hlg: return kCVImageBufferTransferFunction_ITU_R_2100_HLG
        }
    }

    func metadata(from source: CVPixelBuffer) -> NSDictionary {
        var values: [String: Any] = [:]
        if isHDR {
            for key in Self.metadataKeys {
                if let value = CVBufferCopyAttachment(source, key, nil) {
                    values[key as String] = value
                }
            }
        }
        return values as NSDictionary
    }

    func applyAttachments(to buffer: CVPixelBuffer, metadata: NSDictionary) {
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey,
                              isHDR ? kCVImageBufferColorPrimaries_ITU_R_2020 : kCVImageBufferColorPrimaries_ITU_R_709_2,
                              .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, transferFunction, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey,
                              isHDR ? kCVImageBufferYCbCrMatrix_ITU_R_2020 : kCVImageBufferYCbCrMatrix_ITU_R_709_2,
                              .shouldPropagate)
        for key in Self.metadataKeys {
            if isHDR, let value = metadata[key as String] {
                CVBufferSetAttachment(buffer, key, value as CFTypeRef, .shouldPropagate)
            } else {
                // Pools reuse buffers, so remove metadata absent from this frame.
                CVBufferRemoveAttachment(buffer, key)
            }
        }
    }
}
