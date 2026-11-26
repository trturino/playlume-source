import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import CoreML
import IOSurface
import QuartzCore
import RealityKit
import SwiftUI
import Vision

struct StereoDepthRealityView: View {
    let controllerReference: Reference<StreamFrameViewController>
    let frameRate: Int
    let streamAspectRatio: Double
    let model: StereoDepthModel
    let renderingMode: StereoDepthRenderingMode
    let configuration: StereoDepthConfiguration
    let onPresentationStateChange: @MainActor (Bool) -> Void

    @StateObject private var pipeline = StereoDepthPipeline()

    var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                pipeline.installIfNeeded(in: content)
                pipeline.scaleToFit(proxy: geometry, content: content, aspectRatio: streamAspectRatio)
            } update: { content in
                pipeline.installIfNeeded(in: content)
                pipeline.scaleToFit(proxy: geometry, content: content, aspectRatio: streamAspectRatio)
            }
            .task(id: StereoDepthTaskKey(frameRate: frameRate, model: model)) {
                await pipeline.start(
                    controllerReference: controllerReference,
                    frameRate: max(frameRate, 30),
                    model: model,
                    onPresentationStateChange: onPresentationStateChange
                )
            }
            .task(id: StereoDepthConfigurationTaskKey(configuration: configuration, renderingMode: renderingMode)) {
                await pipeline.updateConfiguration(configuration, renderingMode: renderingMode)
            }
            .onDisappear {
                onPresentationStateChange(false)
                controllerReference.object?.setSpatialVideoFPSText(nil)
                pipeline.stop()
            }
            .allowsHitTesting(false)
            .background(Color.clear)
        }
    }
}

private struct StereoDepthTaskKey: Hashable {
    let frameRate: Int
    let model: StereoDepthModel
}

fileprivate struct StereoDepthProcessedFrame {
    let sampleBuffer: CMSampleBuffer
    let processingDuration: CFTimeInterval
}

fileprivate struct StereoDepthRenderedBuffers {
    let left: CVPixelBuffer
    let right: CVPixelBuffer
}

fileprivate struct StereoDepthEffectiveConfiguration {
    let base: StereoDepthConfiguration
    let maximumOutputWidth: Double
    let depthRefreshInterval: Int
    let lowCostMode: Bool
}

private struct StereoDepthConfigurationTaskKey: Hashable {
    let configuration: StereoDepthConfiguration
    let renderingMode: StereoDepthRenderingMode
}

@MainActor
final class StereoDepthPipeline: ObservableObject {
    @Published private(set) var statusText: String?

    private let videoRenderer = AVSampleBufferVideoRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let processor = StereoDepthFrameProcessor()

    private var rootEntity: Entity?
    private var renderTask: Task<Void, Never>?
    private var didPrepareSynchronizer = false
    private var hasPresentedStereoFrame = false
    private var enqueuedStereoFrameCount = 0
    private var fpsWindowStart = Date()
    private var fpsWindowFrameCount = 0
    private var lastEnqueuedPresentationTime: CMTime = .invalid
    private var renderingMode = StereoDepthRenderingMode.defaultValue

    func installIfNeeded(in content: RealityViewContent) {
        guard rootEntity == nil else { return }

        let entity = ModelEntity(
            mesh: .generatePlane(width: 1.0, height: 1.0, cornerRadius: 0.02),
            materials: [VideoMaterial(videoRenderer: videoRenderer)]
        )
        entity.position = [0, 0, 0]

        content.add(entity)
        rootEntity = entity

        if !didPrepareSynchronizer {
            synchronizer.addRenderer(videoRenderer)
            synchronizer.setRate(1.0, time: .zero)
            videoRenderer.presentationTimeExpectation = .monotonicallyIncreasing
            didPrepareSynchronizer = true
        }
    }

    func scaleToFit(proxy: GeometryProxy3D, content: RealityViewContent, aspectRatio: Double) {
        guard let rootEntity else { return }

        let frame = proxy.frame(in: .local)
        let sceneSize = abs(content.convert(frame.size, from: .local, to: .scene))
        let clampedAspect = max(Float(aspectRatio), 0.1)

        let widthScale = sceneSize.x
        let heightScale = sceneSize.y
        let fittedWidth = min(widthScale, heightScale * clampedAspect)
        let fittedHeight = fittedWidth / clampedAspect

        rootEntity.scale = [fittedWidth, fittedHeight, 1]
        rootEntity.position = [0, 0, 0]
    }

    func start(
        controllerReference: Reference<StreamFrameViewController>,
        frameRate: Int,
        model: StereoDepthModel,
        onPresentationStateChange: @escaping @MainActor (Bool) -> Void
    ) async {
        stop()
        onPresentationStateChange(false)
        await MainActor.run {
            controllerReference.object?.setSpatialVideoFPSText(nil)
        }
        print("Stereo depth starting model: \(model.rawValue)")

        await processor.updateModel(model)

        guard Bundle.main.url(forResource: model.rawValue, withExtension: "mlmodelc") != nil else {
            statusText = "Depth model missing from bundle"
            return
        }

        renderTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            await MainActor.run {
                self.statusText = "Stereo depth warming up"
            }

            let fps = max(60, min(frameRate, 120))
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            let frameIntervalNanoseconds = UInt64(1_000_000_000 / UInt64(fps))
            var nextFrameDeadline = DispatchTime.now().uptimeNanoseconds

            while !Task.isCancelled {
                let now = DispatchTime.now().uptimeNanoseconds
                if now < nextFrameDeadline {
                    try? await Task.sleep(nanoseconds: nextFrameDeadline - now)
                }

                nextFrameDeadline &+= frameIntervalNanoseconds

                guard let controller = controllerReference.object else {
                    nextFrameDeadline = DispatchTime.now().uptimeNanoseconds + frameIntervalNanoseconds
                    continue
                }

                let rendererReady = await MainActor.run { self.videoRenderer.isReadyForMoreMediaData }
                guard rendererReady else {
                    continue
                }

                guard let pixelBuffer = controller.copyDisplayedPixelBuffer() else {
                    nextFrameDeadline = DispatchTime.now().uptimeNanoseconds + frameIntervalNanoseconds
                    continue
                }

                do {
                    let presentationTime = await MainActor.run {
                        self.nextPresentationTime(frameDuration: frameDuration)
                    }

                    let sampleBuffer = try await self.processor.makeStereoSampleBuffer(
                        from: pixelBuffer,
                        presentationTime: presentationTime,
                        duration: frameDuration,
                        targetFrameDuration: Double(frameIntervalNanoseconds) / 1_000_000_000
                    )

                    await MainActor.run {
                        self.statusText = nil
                        if self.videoRenderer.isReadyForMoreMediaData {
                            self.videoRenderer.enqueue(sampleBuffer.sampleBuffer)
                            self.enqueuedStereoFrameCount += 1
                            self.recordSpatialVideoFrame(using: controllerReference)
                            if !self.hasPresentedStereoFrame,
                               self.enqueuedStereoFrameCount >= 2 {
                                self.hasPresentedStereoFrame = true
                                onPresentationStateChange(true)
                            }
                        }
                    }
                } catch {
                    print("Stereo depth pipeline error: \(error)")
                    await MainActor.run {
                        self.hasPresentedStereoFrame = false
                        onPresentationStateChange(false)
                        self.statusText = "Stereo depth unavailable"
                    }
                }

                let completionTime = DispatchTime.now().uptimeNanoseconds
                if completionTime > nextFrameDeadline + frameIntervalNanoseconds {
                    nextFrameDeadline = completionTime
                }
            }
        }
    }

    func updateConfiguration(_ configuration: StereoDepthConfiguration, renderingMode: StereoDepthRenderingMode) async {
        self.renderingMode = renderingMode
        lastEnqueuedPresentationTime = .invalid
        await processor.updateConfiguration(configuration, renderingMode: renderingMode)
    }

    func stop() {
        renderTask?.cancel()
        renderTask = nil
        hasPresentedStereoFrame = false
        enqueuedStereoFrameCount = 0
        fpsWindowStart = Date()
        fpsWindowFrameCount = 0
        lastEnqueuedPresentationTime = .invalid
        videoRenderer.flush(removingDisplayedImage: true)
    }

    private func recordSpatialVideoFrame(using controllerReference: Reference<StreamFrameViewController>) {
        fpsWindowFrameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(fpsWindowStart)

        guard elapsed >= 1 else { return }

        let measuredFPS = Double(fpsWindowFrameCount) / elapsed
        controllerReference.object?.setSpatialVideoFPSText(String(format: "%.1f FPS", measuredFPS))
        fpsWindowStart = now
        fpsWindowFrameCount = 0
    }

    private func nextPresentationTime(frameDuration: CMTime) -> CMTime {
        let leadFrames: Int32
        switch renderingMode {
        case .quality:
            leadFrames = 1
        case .performance:
            leadFrames = 2
        }
        let minimumLeadTime = CMTimeMultiply(frameDuration, multiplier: leadFrames)
        let currentSynchronizerTime = synchronizer.currentTime()
        var presentationTime = CMTimeAdd(currentSynchronizerTime, minimumLeadTime)

        if lastEnqueuedPresentationTime.isValid {
            let minimumNextPresentationTime = CMTimeAdd(lastEnqueuedPresentationTime, frameDuration)
            if presentationTime < minimumNextPresentationTime {
                presentationTime = minimumNextPresentationTime
            }
        }

        lastEnqueuedPresentationTime = presentationTime
        return presentationTime
    }
}

actor StereoDepthFrameProcessor {
    private static let inferenceWidth = 518
    private static let inferenceHeight = 392
    private static let adaptiveOutputWidthSteps: [Double] = [1920, 1600, 1440, 1280, 1152, 960, 854, 768]
    private let ciContext = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: StereoVideoColorProfile.workingColorSpace,
        .workingFormat: CIFormat.RGBAh.rawValue,
        .outputColorSpace: StereoVideoColorProfile.sdrColorSpace,
    ])
    private var visionModel: VNCoreMLModel?
    private var depthRequestCache: VNCoreMLRequest?
    private var sequenceRequestHandler = VNSequenceRequestHandler()
    private var cachedDepthImage: CIImage?
    private var cachedPreparedDepthMask: CIImage?
    private var taggedFormatDescription: CMTaggedBufferGroupFormatDescription?
    private var leftPixelBufferPool: CVPixelBufferPool?
    private var rightPixelBufferPool: CVPixelBufferPool?
    private var inferencePixelBufferPool: CVPixelBufferPool?
    private var cachedRenderedBuffers: StereoDepthRenderedBuffers?
    private var cachedSourceFrameIdentifier: UInt64?
    private var outputExtent: CGRect = .zero
    private var outputColorProfile = StereoVideoColorProfile.sdr
    private var outputColorMetadata = NSDictionary()
    private var lastInferenceFrame: Int = 0
    private var processedFrameCount: Int = 0
    private var renderingMode = StereoDepthRenderingMode.defaultValue
    private var adaptiveMaximumOutputWidth: Double?
    private var adaptiveDepthRefreshInterval: Int?
    private var lowCostProcessingEnabled = false
    private var overBudgetStreak = 0
    private var underBudgetStreak = 0
    private var currentModel = StereoDepthModel.defaultValue
    private var configuration = StereoDepthConfiguration.defaultValue

    fileprivate func makeStereoSampleBuffer(
        from pixelBuffer: CVPixelBuffer,
        presentationTime: CMTime,
        duration: CMTime,
        targetFrameDuration: CFTimeInterval
    ) async throws -> StereoDepthProcessedFrame {
        let startTime = CACurrentMediaTime()
        let effectiveConfiguration = effectiveConfiguration()
        let sourceFrameIdentifier = sourceFrameIdentifier(for: pixelBuffer)
        let sourceImage = scaledSourceImage(from: pixelBuffer, maximumOutputWidth: effectiveConfiguration.maximumOutputWidth)
        let colorProfile = StereoVideoColorProfile(source: pixelBuffer)
        try ensurePixelBufferPools(for: sourceImage.extent, colorProfile: colorProfile)
        let colorMetadata = colorProfile.metadata(from: pixelBuffer)
        if !outputColorMetadata.isEqual(colorMetadata) {
            outputColorMetadata = colorMetadata
            taggedFormatDescription = nil
            cachedRenderedBuffers = nil
            cachedSourceFrameIdentifier = nil
        }
        let configuration = effectiveConfiguration.base
        processedFrameCount += 1

        if cachedDepthImage != nil,
           cachedPreparedDepthMask != nil,
           let cachedRenderedBuffers,
           cachedSourceFrameIdentifier == sourceFrameIdentifier {
            let sampleBuffer = try makeSampleBuffer(
                using: cachedRenderedBuffers,
                presentationTime: presentationTime,
                duration: duration
            )
            return StereoDepthProcessedFrame(
                sampleBuffer: sampleBuffer,
                processingDuration: CACurrentMediaTime() - startTime
            )
        }

        if cachedDepthImage == nil || processedFrameCount - lastInferenceFrame >= effectiveConfiguration.depthRefreshInterval {
            cachedDepthImage = try await estimateDepthImage(for: pixelBuffer)
            cachedPreparedDepthMask = nil
            lastInferenceFrame = processedFrameCount
        }

        guard let depthImage = cachedDepthImage else {
            throw StereoDepthError.depthUnavailable
        }

        let preparedDepthMask = preparedDepthMask(
            from: depthImage,
            sourceExtent: sourceImage.extent,
            configuration: configuration
        )

        let disparityScale = Float(max(sourceImage.extent.width, sourceImage.extent.height)) * Float(configuration.strength)
        let leftImage = try makeEyeImage(
            sourceImage: sourceImage,
            preparedDepthMask: preparedDepthMask,
            scale: -disparityScale,
            configuration: configuration,
            lowCostMode: effectiveConfiguration.lowCostMode
        )
        let rightImage = try makeEyeImage(
            sourceImage: sourceImage,
            preparedDepthMask: preparedDepthMask,
            scale: disparityScale,
            configuration: configuration,
            lowCostMode: effectiveConfiguration.lowCostMode
        )

        let leftBuffer = try makePixelBuffer(from: leftPixelBufferPool)
        let rightBuffer = try makePixelBuffer(from: rightPixelBufferPool)

        colorProfile.applyAttachments(to: leftBuffer, metadata: colorMetadata)
        colorProfile.applyAttachments(to: rightBuffer, metadata: colorMetadata)

        ciContext.render(leftImage, to: leftBuffer, bounds: sourceImage.extent, colorSpace: colorProfile.colorSpace)
        ciContext.render(rightImage, to: rightBuffer, bounds: sourceImage.extent, colorSpace: colorProfile.colorSpace)

        let renderedBuffers = StereoDepthRenderedBuffers(left: leftBuffer, right: rightBuffer)
        cachedRenderedBuffers = renderedBuffers
        cachedSourceFrameIdentifier = sourceFrameIdentifier
        let sampleBuffer = try makeSampleBuffer(
            using: renderedBuffers,
            presentationTime: presentationTime,
            duration: duration
        )
        let processingDuration = CACurrentMediaTime() - startTime
        adaptPerformance(
            processingDuration: processingDuration,
            targetFrameDuration: targetFrameDuration,
            baseConfiguration: configuration
        )
        return StereoDepthProcessedFrame(
            sampleBuffer: sampleBuffer,
            processingDuration: processingDuration
        )
    }

    func updateConfiguration(_ configuration: StereoDepthConfiguration, renderingMode: StereoDepthRenderingMode) {
        self.configuration = configuration.clamped()
        self.renderingMode = renderingMode
        cachedPreparedDepthMask = nil
        cachedRenderedBuffers = nil
        cachedSourceFrameIdentifier = nil
        resetAdaptiveState()
    }

    func updateModel(_ model: StereoDepthModel) {
        guard currentModel != model else { return }
        print("Stereo depth switching model from \(currentModel.rawValue) to \(model.rawValue)")
        currentModel = model
        visionModel = nil
        depthRequestCache = nil
        cachedDepthImage = nil
        cachedPreparedDepthMask = nil
        cachedRenderedBuffers = nil
        cachedSourceFrameIdentifier = nil
        processedFrameCount = 0
        lastInferenceFrame = 0
        sequenceRequestHandler = VNSequenceRequestHandler()
        resetAdaptiveState()
    }

    private func estimateDepthImage(for pixelBuffer: CVPixelBuffer) async throws -> CIImage {
        try ensureInferencePixelBufferPool()
        let preparedPixelBuffer = try makePixelBuffer(from: inferencePixelBufferPool)
        var inferenceImage = CIImage(cvPixelBuffer: pixelBuffer)
        if StereoVideoColorProfile(source: pixelBuffer).isHDR {
            let toneMap = CIFilter.toneMapHeadroom()
            toneMap.inputImage = inferenceImage
            toneMap.targetHeadroom = 1
            inferenceImage = toneMap.outputImage ?? inferenceImage
        }
        let preparedImage = inferenceImage
            .transformed(
                by: CGAffineTransform(
                    scaleX: CGFloat(Self.inferenceWidth) / max(CGFloat(CVPixelBufferGetWidth(pixelBuffer)), 1),
                    y: CGFloat(Self.inferenceHeight) / max(CGFloat(CVPixelBufferGetHeight(pixelBuffer)), 1)
                )
            )
            .cropped(to: CGRect(x: 0, y: 0, width: Self.inferenceWidth, height: Self.inferenceHeight))

        ciContext.render(preparedImage, to: preparedPixelBuffer, bounds: preparedImage.extent,
                         colorSpace: StereoVideoColorProfile.sdrColorSpace)

        let request = try depthRequest()
        try sequenceRequestHandler.perform([request], on: preparedPixelBuffer)

        if let observation = request.results?.first as? VNPixelBufferObservation {
            return CIImage(cvPixelBuffer: observation.pixelBuffer)
        }

        if let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
           let outputBuffer = observation.featureValue.imageBufferValue {
            return CIImage(cvPixelBuffer: outputBuffer)
        }

        print("Stereo depth inference returned no usable observation")
        throw StereoDepthError.depthUnavailable
    }

    private func depthRequest() throws -> VNCoreMLRequest {
        if let depthRequestCache {
            return depthRequestCache
        }

        if visionModel == nil {
            guard let modelURL = Bundle.main.url(forResource: currentModel.rawValue, withExtension: "mlmodelc") else {
                throw StereoDepthError.modelMissing
            }

            let startTime = CFAbsoluteTimeGetCurrent()
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            let model = try MLModel(contentsOf: modelURL, configuration: configuration)
            visionModel = try VNCoreMLModel(for: model)
            let loadDuration = CFAbsoluteTimeGetCurrent() - startTime
            print(
                "Stereo depth loaded model \(currentModel.rawValue) from \(modelURL.lastPathComponent) in \(String(format: "%.3f", loadDuration))s"
            )
        }

        let request = VNCoreMLRequest(model: visionModel!)
        request.imageCropAndScaleOption = .scaleFill
        request.preferBackgroundProcessing = false
        depthRequestCache = request
        return request
    }

    private func preparedDepthMask(
        from depthImage: CIImage,
        sourceExtent: CGRect,
        configuration: StereoDepthConfiguration
    ) -> CIImage {
        if let cachedPreparedDepthMask {
            return cachedPreparedDepthMask
        }

        var resizedDepth = depthImage
            .transformed(
                by: CGAffineTransform(
                    scaleX: sourceExtent.width / max(depthImage.extent.width, 1),
                    y: sourceExtent.height / max(depthImage.extent.height, 1)
                )
            )
            .cropped(to: sourceExtent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: configuration.depthContrast,
                kCIInputBrightnessKey: configuration.depthBrightness,
            ])
            .applyingFilter("CIGammaAdjust", parameters: [
                "inputPower": configuration.depthGamma,
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(
                    x: configuration.depthClampMin,
                    y: configuration.depthClampMin,
                    z: configuration.depthClampMin,
                    w: 0.0
                ),
                "inputMaxComponents": CIVector(
                    x: configuration.depthClampMax,
                    y: configuration.depthClampMax,
                    z: configuration.depthClampMax,
                    w: 1.0
                ),
            ])
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: configuration.depthBlurRadius,
            ])
            .cropped(to: sourceExtent)

        if configuration.invertDepth {
            resizedDepth = resizedDepth.applyingFilter("CIColorInvert")
        }

        cachedPreparedDepthMask = resizedDepth
        return resizedDepth
    }

    private func makeEyeImage(
        sourceImage: CIImage,
        preparedDepthMask: CIImage,
        scale: Float,
        configuration: StereoDepthConfiguration,
        lowCostMode: Bool
    ) throws -> CIImage {
        let resizedDepth = preparedDepthMask

        let foregroundOffset = CGFloat(scale) * configuration.foregroundShift
        let backgroundOffset = CGFloat(scale) * configuration.backgroundShift
        let clampedSourceImage = sourceImage.clampedToExtent()

        var foreground = clampedSourceImage
            .transformed(by: CGAffineTransform(translationX: foregroundOffset, y: 0))
            .cropped(to: sourceImage.extent)
        if !lowCostMode, configuration.foregroundSharpnessRadius > 0, configuration.foregroundSharpnessIntensity > 0 {
            foreground = foreground.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: configuration.foregroundSharpnessRadius,
                kCIInputIntensityKey: configuration.foregroundSharpnessIntensity,
            ])
        }
        let background = clampedSourceImage
            .transformed(by: CGAffineTransform(translationX: backgroundOffset, y: 0))
            .cropped(to: sourceImage.extent)

        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = foreground
        blendFilter.backgroundImage = background
        blendFilter.maskImage = resizedDepth

        guard let outputImage = blendFilter.outputImage?.cropped(to: sourceImage.extent) else {
            throw StereoDepthError.renderFailed
        }

        // Preserve HDR luminance; the legacy SDR exposure/gamma adjustments
        // change the brightness of HDR highlights and vary by rendering mode.
        guard !lowCostMode && !outputColorProfile.isHDR else {
            return outputImage
        }

        let correctedOutputImage = outputImage
            .applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: -0.08,
            ])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.0,
                kCIInputContrastKey: 1.02,
                kCIInputBrightnessKey: 0.0,
            ])
            .applyingFilter("CIGammaAdjust", parameters: [
                "inputPower": 1.02,
            ])
            .cropped(to: sourceImage.extent)

        return correctedOutputImage
    }

    private func scaledSourceImage(from pixelBuffer: CVPixelBuffer, maximumOutputWidth: Double) -> CIImage {
        // Core Image reads the source transfer function and primaries from the
        // buffer attachments. Assigning BT.709 here reinterprets PQ as SDR.
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let maxDimension = max(image.extent.width, image.extent.height)

        let scale = min(maximumOutputWidth / maxDimension, 1)
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard StereoVideoColorProfile(source: pixelBuffer).isHDR else {
            return scaledImage
        }

        // Crop subpixel/odd edges rather than leaving unwritten padding in
        // chroma-subsampled eye buffers after adaptive resolution changes.
        return scaledImage.cropped(to: CGRect(
            x: 0, y: 0,
            width: max(2, floor(scaledImage.extent.width / 2) * 2),
            height: max(2, floor(scaledImage.extent.height / 2) * 2)
        ))
    }

    private func ensurePixelBufferPools(for extent: CGRect, colorProfile: StereoVideoColorProfile) throws {
        guard extent != outputExtent || colorProfile != outputColorProfile || leftPixelBufferPool == nil || rightPixelBufferPool == nil else {
            return
        }

        if colorProfile != outputColorProfile {
            cachedDepthImage = nil
        }
        outputExtent = extent
        outputColorProfile = colorProfile
        cachedPreparedDepthMask = nil
        cachedRenderedBuffers = nil
        cachedSourceFrameIdentifier = nil
        taggedFormatDescription = nil
        let width = Int(extent.width)
        let height = Int(extent.height)
        leftPixelBufferPool = try makePixelBufferPool(width: width, height: height, pixelFormat: colorProfile.pixelFormat)
        rightPixelBufferPool = try makePixelBufferPool(width: width, height: height, pixelFormat: colorProfile.pixelFormat)
    }

    private func ensureInferencePixelBufferPool() throws {
        guard inferencePixelBufferPool == nil else {
            return
        }

        inferencePixelBufferPool = try makePixelBufferPool(width: Self.inferenceWidth, height: Self.inferenceHeight)
    }

    private func makePixelBufferPool(width: Int, height: Int, pixelFormat: OSType = kCVPixelFormatType_32BGRA) throws -> CVPixelBufferPool {
        var pool: CVPixelBufferPool?
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 6,
        ]

        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            attributes as CFDictionary,
            &pool
        )

        guard status == kCVReturnSuccess, let pool else {
            throw StereoDepthError.renderFailed
        }

        return pool
    }

    private func makePixelBuffer(from pool: CVPixelBufferPool?) throws -> CVPixelBuffer {
        guard let pool else {
            throw StereoDepthError.renderFailed
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)

        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw StereoDepthError.renderFailed
        }

        return pixelBuffer
    }

    private func makeSampleBuffer(
        using renderedBuffers: StereoDepthRenderedBuffers,
        presentationTime: CMTime,
        duration: CMTime
    ) throws -> CMSampleBuffer {
        let taggedBuffers = [
            CMTaggedBuffer(tags: [.videoLayerID(0), .stereoView(.leftEye), .mediaType(.video)], pixelBuffer: renderedBuffers.left),
            CMTaggedBuffer(tags: [.videoLayerID(1), .stereoView(.rightEye), .mediaType(.video)], pixelBuffer: renderedBuffers.right),
        ]

        if taggedFormatDescription == nil {
            taggedFormatDescription = CMFormatDescription(taggedBuffers: taggedBuffers)
        }

        return CMSampleBuffer(
            taggedBuffers: taggedBuffers,
            presentationTimeStamp: presentationTime,
            duration: duration,
            formatDescription: taggedFormatDescription!
        )
    }

    private func sourceFrameIdentifier(for pixelBuffer: CVPixelBuffer) -> UInt64 {
        if let ioSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() {
            return UInt64(IOSurfaceGetID(ioSurface))
        }

        return UInt64(UInt(bitPattern: Unmanaged.passUnretained(pixelBuffer).toOpaque()))
    }

    private func effectiveConfiguration() -> StereoDepthEffectiveConfiguration {
        let baseConfiguration = configuration.clamped()
        let adaptiveModeEnabled = renderingMode == .performance
        return StereoDepthEffectiveConfiguration(
            base: baseConfiguration,
            maximumOutputWidth: adaptiveModeEnabled ? min(adaptiveMaximumOutputWidth ?? baseConfiguration.maximumOutputWidth, baseConfiguration.maximumOutputWidth) : baseConfiguration.maximumOutputWidth,
            depthRefreshInterval: adaptiveModeEnabled ? max(adaptiveDepthRefreshInterval ?? baseConfiguration.depthRefreshInterval, baseConfiguration.depthRefreshInterval) : baseConfiguration.depthRefreshInterval,
            lowCostMode: adaptiveModeEnabled && lowCostProcessingEnabled
        )
    }

    private func resetAdaptiveState() {
        adaptiveMaximumOutputWidth = nil
        adaptiveDepthRefreshInterval = nil
        lowCostProcessingEnabled = false
        overBudgetStreak = 0
        underBudgetStreak = 0
    }

    private func adaptPerformance(
        processingDuration: CFTimeInterval,
        targetFrameDuration: CFTimeInterval,
        baseConfiguration: StereoDepthConfiguration
    ) {
        guard renderingMode == .performance else {
            return
        }

        let budget = max(targetFrameDuration, 1.0 / 120.0)
        let utilization = processingDuration / budget

        if utilization > 1.05 {
            overBudgetStreak += 1
            underBudgetStreak = 0
            if overBudgetStreak >= 3 {
                degradePerformance(baseConfiguration: baseConfiguration)
                overBudgetStreak = 0
            }
            return
        }

        if utilization < 0.72 {
            underBudgetStreak += 1
            overBudgetStreak = 0
            if underBudgetStreak >= 18 {
                relaxPerformance(baseConfiguration: baseConfiguration)
                underBudgetStreak = 0
            }
            return
        }

        overBudgetStreak = 0
        underBudgetStreak = 0
    }

    private func degradePerformance(baseConfiguration: StereoDepthConfiguration) {
        if !lowCostProcessingEnabled {
            lowCostProcessingEnabled = true
            return
        }

        let currentDepthRefreshInterval = adaptiveDepthRefreshInterval ?? baseConfiguration.depthRefreshInterval
        let maxDepthRefreshInterval = max(baseConfiguration.depthRefreshInterval, 12)
        if currentDepthRefreshInterval < maxDepthRefreshInterval {
            adaptiveDepthRefreshInterval = currentDepthRefreshInterval + 1
            return
        }

        let currentWidth = adaptiveMaximumOutputWidth ?? baseConfiguration.maximumOutputWidth
        if let nextWidth = nextLowerOutputWidth(below: currentWidth) {
            adaptiveMaximumOutputWidth = nextWidth
            cachedPreparedDepthMask = nil
        }
    }

    private func relaxPerformance(baseConfiguration: StereoDepthConfiguration) {
        let currentWidth = adaptiveMaximumOutputWidth ?? baseConfiguration.maximumOutputWidth
        if currentWidth < baseConfiguration.maximumOutputWidth {
            let nextWidth = nextHigherOutputWidth(above: currentWidth, cappedBy: baseConfiguration.maximumOutputWidth)
            adaptiveMaximumOutputWidth = nextWidth >= baseConfiguration.maximumOutputWidth ? nil : nextWidth
            cachedPreparedDepthMask = nil
            return
        }

        let currentDepthRefreshInterval = adaptiveDepthRefreshInterval ?? baseConfiguration.depthRefreshInterval
        if currentDepthRefreshInterval > baseConfiguration.depthRefreshInterval {
            let nextInterval = currentDepthRefreshInterval - 1
            adaptiveDepthRefreshInterval = nextInterval == baseConfiguration.depthRefreshInterval ? nil : nextInterval
            return
        }

        if lowCostProcessingEnabled {
            lowCostProcessingEnabled = false
        }
    }

    private func nextLowerOutputWidth(below width: Double) -> Double? {
        let sortedWidths = Self.adaptiveOutputWidthSteps.sorted(by: >)
        return sortedWidths.first(where: { $0 < width })
    }

    private func nextHigherOutputWidth(above width: Double, cappedBy maximumWidth: Double) -> Double {
        let sortedWidths = Self.adaptiveOutputWidthSteps.sorted()
        return sortedWidths.first(where: { $0 > width && $0 <= maximumWidth }) ?? maximumWidth
    }
}

enum StereoDepthError: Error {
    case modelMissing
    case depthUnavailable
    case renderFailed
}
