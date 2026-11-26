import SwiftUI
import GameController
import UIKit

struct AppContentView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @State private var dimPassthrough = true
    @State private var streamControllerReference = Reference<StreamFrameViewController>()
    @State private var stereoPresentationReady = false
    @StateObject private var keyboardController = StreamKeyboardController
        .create()
    
    var body: some View {
        if viewModel.activelyStreaming {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    HStack {
                        if viewModel.stereoDepthEnabled && !stereoPresentationReady {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Close", systemImage: "xmark") {
                            viewModel.stopStreaming()
                        }
                        Button("Toggle Dimming", systemImage: dimPassthrough ? "moon.fill" : "moon") {
                            dimPassthrough.toggle()
                        }
                        Button("Keyboard", systemImage: "keyboard") {
                            keyboardController.activateKeyboard()
                        }
                        Button("Stereo Depth", systemImage: viewModel.stereoDepthEnabled ? "visionpro.fill" : "visionpro") {
                            viewModel.stereoDepthEnabled.toggle()
                            if !viewModel.stereoDepthEnabled {
                                stereoPresentationReady = false
                            }
                        }
                        if viewModel.stereoDepthEnabled {
                            StereoDepthModePicker(renderingMode: $viewModel.stereoDepthRenderingMode)
                        }
                    }
                    .labelStyle(.iconOnly)
                    .padding()
                    .overlay {
                        StreamKeyboardInput(controller: keyboardController)
                            .frame(width: 12, height: 12)
                            .opacity(0.015)
                            .allowsHitTesting(false)
                    }
                    .glassBackgroundEffect()
                    .frame(maxWidth: .infinity, alignment: .center)

                    ZStack {
                        StreamView(
                            streamConfig: $viewModel.currentStreamConfig,
                            stereoDepthEnabled: .constant(viewModel.stereoDepthEnabled && stereoPresentationReady),
                            controllerReference: streamControllerReference
                        )
                        .handlesGameControllerEvents(matching: .gamepad)
                        .spatialOverlay(alignment: .center) {
                            if viewModel.stereoDepthEnabled {
                                StereoDepthRealityView(
                                    controllerReference: streamControllerReference,
                                    frameRate: Int(viewModel.currentStreamConfig.frameRate),
                                    streamAspectRatio: Double(viewModel.currentStreamConfig.width) / Double(max(viewModel.currentStreamConfig.height, 1)),
                                    model: viewModel.stereoDepthModel,
                                    renderingMode: viewModel.stereoDepthRenderingMode,
                                    configuration: viewModel.stereoDepthConfiguration
                                ) { isReady in
                                    stereoPresentationReady = isReady
                                }
                                .opacity(stereoPresentationReady ? 1 : 0)
                            }
                        }
                    }
                    .aspectRatio(
                        CGSize(
                            width: CGFloat(viewModel.currentStreamConfig.width),
                            height: CGFloat(viewModel.currentStreamConfig.height)
                        ),
                        contentMode: .fit
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 30.0))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(24)
            .onAppear {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                let geometryRequest = UIWindowScene.GeometryPreferences.Vision(resizingRestrictions: .freeform)
                windowScene.requestGeometryUpdate(geometryRequest)
            }
            .onDisappear {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                let geometryRequest = UIWindowScene.GeometryPreferences.Vision(resizingRestrictions: .freeform)
                windowScene.requestGeometryUpdate(geometryRequest)
            }
//            .preferredSurroundingsEffect(dimPassthrough ? .systemDark : .colorMultiply(Color(red: 1.15, green: 1.2, blue: 1.4)))
            .onDisappear {
                stereoPresentationReady = false
                viewModel.stereoDepthEnabled = false
            }
        } else {
            NavigationStack {
                MainView()
                    .navigationDestination(isPresented: $viewModel.isShowingHostPage) {
                        HostView()
                    }
            }
            .environmentObject(viewModel)
            .onAppear {
                keyboardController.reset()
            }
        }
    }
}

private struct StreamKeyboardInput: UIViewRepresentable {
    @ObservedObject var controller: StreamKeyboardController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> KeyboardHostView {
        let hostView = KeyboardHostView()
        hostView.textField.delegate = context.coordinator
        hostView.textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.onKeyboardPressed(_:)),
            for: .editingChanged
        )
        context.coordinator.textField = hostView.textField
        context.coordinator.resetTextField()
        return hostView
    }

    func updateUIView(_ uiView: KeyboardHostView, context: Context) {
        context.coordinator.textField = uiView.textField
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let controller: StreamKeyboardController
        weak var textField: UITextField?

        init(controller: StreamKeyboardController) {
            self.controller = controller
            super.init()
            controller.activate = { [weak self] in
                self?.activateKeyboard()
            }
            controller.resetHandler = { [weak self] in
                self?.resetTextField()
            }
        }

        private func activateKeyboard() {
            guard let textField else { return }
            resetTextField()

            DispatchQueue.main.async {
                if textField.isFirstResponder {
                    textField.resignFirstResponder()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.resetTextField()
                        textField.becomeFirstResponder()
                    }
                } else {
                    textField.becomeFirstResponder()
                }
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            SDLMainWrapper.sendReturn()
            resetTextField()
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            resetTextField()
            controller.reset()
        }

        @objc func onKeyboardPressed(_ textField: UITextField) {
            let inputText = textField.text ?? ""

            if inputText.isEmpty {
                SDLMainWrapper.sendBackspace()
            } else if inputText.count > KeyboardHostView.sentinel.count {
                let typedText = String(inputText.dropFirst(KeyboardHostView.sentinel.count))
                SDLMainWrapper.sendText(typedText)
            }

            resetTextField()
        }

        func resetTextField() {
            guard let textField else { return }
            textField.text = KeyboardHostView.sentinel
            let end = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: end, to: end)
        }
    }
}

private final class StreamKeyboardController: ObservableObject {
    fileprivate var activate: (() -> Void)?
    fileprivate var resetHandler: (() -> Void)?

    static func create() -> StreamKeyboardController {
        StreamKeyboardController()
    }

    func activateKeyboard() {
        activate?()
    }

    func reset() {
        resetHandler?()
    }
}

private final class KeyboardHostView: UIView {
    static let sentinel = "0"

    let textField = UITextField(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false
        backgroundColor = .clear

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.keyboardType = .default
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.textColor = .clear
        textField.tintColor = .clear
        textField.backgroundColor = .clear

        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 12),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 12)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct StereoDepthModePicker: View {
    @Binding var renderingMode: StereoDepthRenderingMode

    var body: some View {
        Picker("Stereo Mode", selection: $renderingMode) {
            ForEach(StereoDepthRenderingMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 240)
        .help(renderingMode.detail)
    }
}
