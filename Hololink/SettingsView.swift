//

import SwiftUI

struct SettingsView: View {
    @Binding public var settings: TemporarySettings
    @State private var isShowingResolutionPicker = false
    @State private var isShowingLicenses = false

    private let heroPalette = TilePalette.hero
    private let videoPalette = TilePalette.video
    private let controlsPalette = TilePalette.controls
    private let streamingPalette = TilePalette.streaming

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heroCard

                    settingsSection("Video", subtitle: "Stream quality, codec, and pacing.", width: geometry.size.width) {
                        Button {
                            isShowingResolutionPicker = true
                        } label: {
                            SettingsTile(
                                title: "Resolution",
                                subtitle: settings.resolution.description,
                                systemImage: "display",
                                palette: videoPalette
                            ) {
                                Label("Choose size", systemImage: "slider.horizontal.3")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)

                        SettingsTile(
                            title: "Framerate",
                            subtitle: "\(settings.framerate) FPS",
                            systemImage: "gauge.with.dots.needle.50percent",
                            palette: videoPalette
                        ) {
                            Picker("Framerate", selection: $settings.framerate) {
                                ForEach(Self.framerateTable, id: \.self) { framerate in
                                    Text("\(framerate) FPS").tag(framerate)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        SettingsTile(
                            title: "Bitrate",
                            subtitle: settings.bitrateLabel,
                            systemImage: "speedometer",
                            palette: videoPalette
                        ) {
                            Picker("Bitrate", selection: $settings.bitrate) {
                                ForEach(Self.bitrateTable, id: \.self) { bitrate in
                                    Text("\(bitrate / 1000) Mbps").tag(bitrate)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        SettingsTile(
                            title: "Preferred Codec",
                            subtitle: settings.preferredCodec.label,
                            systemImage: "bolt.horizontal.circle",
                            palette: videoPalette
                        ) {
                            Picker("Preferred Codec", selection: $settings.preferredCodec) {
                                Text("Auto").tag(PreferredCodec.auto)
                                Text("H.264").tag(PreferredCodec.h264)
                                Text("HEVC").tag(PreferredCodec.hevc)
                                Text("AV1").tag(PreferredCodec.av1)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        SettingsTile(
                            title: "HDR",
                            subtitle: settings.enableHdr ? "Expanded dynamic range" : "Standard dynamic range",
                            systemImage: "sun.max.trianglebadge.exclamationmark",
                            palette: videoPalette
                        ) {
                            Toggle("Enable HDR", isOn: $settings.enableHdr)
                                .labelsHidden()
                                .tint(videoPalette.toggleTint)
                                .toggleStyle(.switch)
                        }

                        SettingsTile(
                            title: "Frame Pacing",
                            subtitle: settings.useFramePacing ? "Smoothest video" : "Lowest latency",
                            systemImage: "waveform.path.ecg.rectangle",
                            palette: videoPalette
                        ) {
                            Picker("Frame Pacing", selection: $settings.useFramePacing) {
                                Text("Lowest Latency").tag(false)
                                Text("Smoothest Video").tag(true)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    settingsSection("Controls", subtitle: "Touch input, controllers, and overlays.", width: geometry.size.width) {
                        SettingsTile(
                            title: "Touch Mode",
                            subtitle: settings.absoluteTouchMode ? "Touchscreen" : "Touchpad",
                            systemImage: "hand.tap",
                            palette: controlsPalette
                        ) {
                            Picker("Touch Mode", selection: $settings.absoluteTouchMode) {
                                Text("Touchpad").tag(false)
                                Text("Touchscreen").tag(true)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        SettingsTile(
                            title: "Multi-Controller",
                            subtitle: settings.multiController ? "Automatic pairing" : "Single controller",
                            systemImage: "person.2",
                            palette: controlsPalette
                        ) {
                            Picker("Multi-Controller Mode", selection: $settings.multiController) {
                                Text("Single").tag(false)
                                Text("Auto").tag(true)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        SettingsTile(
                            title: "Button Layout",
                            subtitle: settings.swapABXYButtons ? "Swapped A/B and X/Y" : "Standard layout",
                            systemImage: "button.programmable",
                            palette: controlsPalette
                        ) {
                            Toggle("Swap A/B and X/Y Buttons", isOn: $settings.swapABXYButtons)
                                .labelsHidden()
                                .tint(controlsPalette.toggleTint)
                                .toggleStyle(.switch)
                        }

                        SettingsTile(
                            title: "Citrix X1 Mouse",
                            subtitle: settings.btMouseSupport ? "Enabled for external mice" : "Disabled",
                            systemImage: "cursorarrow.motionlines",
                            palette: controlsPalette
                        ) {
                            Toggle("Citrix X1 Mouse Support", isOn: $settings.btMouseSupport)
                                .labelsHidden()
                                .tint(controlsPalette.toggleTint)
                                .toggleStyle(.switch)
                        }

                        SettingsTile(
                            title: "Stats Overlay",
                            subtitle: settings.statsOverlay ? "Visible during streaming" : "Hidden during streaming",
                            systemImage: "chart.bar.xaxis",
                            palette: controlsPalette
                        ) {
                            Toggle("Statistics Overlay", isOn: $settings.statsOverlay)
                                .labelsHidden()
                                .tint(controlsPalette.toggleTint)
                                .toggleStyle(.switch)
                        }
                    }

                    settingsSection("Streaming", subtitle: "Audio routing and system-side preferences.", width: geometry.size.width) {
                        SettingsTile(
                            title: "Optimize Games",
                            subtitle: settings.optimizeGames ? "Host tweaks applied when possible" : "Leave host settings unchanged",
                            systemImage: "wand.and.stars",
                            palette: streamingPalette
                        ) {
                            Toggle("Optimize Game Settings", isOn: $settings.optimizeGames)
                                .labelsHidden()
                                .tint(streamingPalette.toggleTint)
                                .toggleStyle(.switch)
                        }

                        SettingsTile(
                            title: "Audio Output",
                            subtitle: settings.playAudioOnPC ? "Play on PC" : "Play on headset",
                            systemImage: "speaker.wave.2",
                            palette: streamingPalette
                        ) {
                            Toggle("Play Audio on PC", isOn: $settings.playAudioOnPC)
                                .labelsHidden()
                                .tint(streamingPalette.toggleTint)
                                .toggleStyle(.switch)
                        }
                    }
                    Button {
                        isShowingLicenses = true
                    } label: {
                        Label("Open Source Licenses", systemImage: "doc.text")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
            .navigationTitle("Settings")
            .onDisappear {
                settings.save()
            }
        }
        .sheet(isPresented: $isShowingResolutionPicker) {
            resolutionPicker
        }
        .sheet(isPresented: $isShowingLicenses) {
            NavigationStack {
                List {
                    Section {
                        Text("Playlume is based on Moonlight and is licensed under the GNU GPL version 3. It also uses FFmpeg under the GNU LGPL version 2.1 or later.")
                        Link("Download source code", destination: URL(string: "https://github.com/trturino/playlume-source/releases")!)
                    }
                    if let noticesURL = Bundle.main.url(forResource: "OpenSourceNotices", withExtension: "txt"),
                       let notices = try? String(contentsOf: noticesURL, encoding: .utf8) {
                        Section("License notices") {
                            Text(notices)
                                .textSelection(.enabled)
                        }
                    }
                }
                .navigationTitle("Open Source Licenses")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingLicenses = false }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Streaming Profile")
                .font(.title2.weight(.semibold))

            HStack(spacing: 12) {
                summaryPill(title: settings.resolution.description, systemImage: "display")
                summaryPill(title: "\(settings.framerate) FPS", systemImage: "gauge")
                summaryPill(title: settings.bitrateLabel, systemImage: "speedometer")
                summaryPill(title: settings.preferredCodec.label, systemImage: "bolt.horizontal.circle")
            }

            Text("Adjust visual quality, controls, and routing from a single dashboard instead of a linear form.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(heroPalette.primary)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.16),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
    }

    private var resolutionPicker: some View {
        NavigationStack {
            List {
                Section("Custom") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Set an exact streaming resolution.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            TextField("Width", value: $settings.resolution.width, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)

                            Text("x")
                                .foregroundStyle(.secondary)

                            TextField("Height", value: $settings.resolution.height, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                        }

                        Text("Current: \(settings.resolution.width) x \(settings.resolution.height)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }

                ForEach(Self.resolutionsGroupedByType, id: \.0) { aspectRatio, resolutions in
                    Section(aspectRatio.casualDescription) {
                        ForEach(resolutions, id: \.self) { resolution in
                            Button {
                                settings.resolution = resolution
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(resolution.description)
                                            .font(.headline)
                                        Text("\(resolution.width) x \(resolution.height)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if settings.resolution == resolution {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .glassBackgroundEffect(.plate, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .navigationTitle("Resolution")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingResolutionPicker = false
                    }
                }
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        subtitle: String,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns(for: width), alignment: .leading, spacing: 20) {
                content()
            }
        }
    }

    private func summaryPill(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.14), in: Capsule())
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        let contentWidth = max(width - 56, 240)
        let targetTileWidth: CGFloat = 300
        let columnCount = max(Int(contentWidth / targetTileWidth), 1)
        return Array(
            repeating: GridItem(.flexible(minimum: 220, maximum: 420), spacing: 20, alignment: .top),
            count: columnCount
        )
    }
}

private struct SettingsTile<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let palette: TilePalette
    @ViewBuilder let content: Content

    private let tileShape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    private let tileHeight: CGFloat = 196

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.18))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .center) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tint(.white)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight, alignment: .topLeading)
        .containerShape(tileShape)
        .contentShape(.interaction, tileShape)
        .contentShape(.hoverEffect, tileShape)
        .background {
            tileShape
                .fill(palette.primary)
                .overlay {
                    tileShape
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.14),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            tileShape
                .strokeBorder(
                    .white.opacity(0.18),
                    lineWidth: 1
                )
        }
        .shadow(color: palette.primary.opacity(0.24), radius: 24, x: 0, y: 16)
        .hoverEffect(.highlight)
    }
}

private struct TilePalette {
    let primary: Color
    let toggleTint: Color

    static let hero = TilePalette(
        primary: Color(red: 0.31, green: 0.26, blue: 0.78),
        toggleTint: Color(red: 0.13, green: 0.10, blue: 0.28)
    )
    static let video = TilePalette(
        primary: Color(red: 0.21, green: 0.54, blue: 0.93),
        toggleTint: Color(red: 0.05, green: 0.18, blue: 0.40)
    )
    static let controls = TilePalette(
        primary: Color(red: 0.73, green: 0.30, blue: 0.58),
        toggleTint: Color(red: 0.34, green: 0.07, blue: 0.24)
    )
    static let streaming = TilePalette(
        primary: Color(red: 0.10, green: 0.63, blue: 0.58),
        toggleTint: Color(red: 0.03, green: 0.28, blue: 0.26)
    )
}

private extension TemporarySettings {
    var resolution: SettingsView.Resolution {
        get {
            SettingsView.Resolution(width: Int(width), height: Int(height))
        }
        set {
            width = Int32(newValue.width)
            height = Int32(newValue.height)
        }
    }

    var bitrateLabel: String {
        "\(bitrate / 1000) Mbps"
    }
}

private extension PreferredCodec {
    var label: String {
        switch self {
        case .auto:
            "Auto"
        case .h264:
            "H.264"
        case .hevc:
            "HEVC"
        case .av1:
            "AV1"
        @unknown default:
            "Unknown"
        }
    }
}

extension SettingsView {
    struct AspectRatio: Equatable, Hashable, Comparable {
        // Always stored as reduced values
        private let width: Int
        private let height: Int

        init(width: Int, height: Int) {
            let reduced = simplifyFraction(numerator: width, denominator: height)
            self.width = reduced.numerator
            self.height = reduced.denominator
        }

        var casualDescription: LocalizedStringKey {
            switch self {
            case AspectRatio(width: 16, height: 9):
                "Widescreen (TV)"
            case AspectRatio(width: 16, height: 10):
                "Widescreen (PC)"
            case AspectRatio(width: 4, height: 3):
                "4:3"
            case AspectRatio(width: 64, height: 27):
                "Ultrawide (64:27)"
            case AspectRatio(width: 43, height: 18):
                "Ultrawide (43:18)"
            case AspectRatio(width: 32, height: 9):
                "Super-Ultrawide"
            default:
                "\(width)-by-\(height)"
            }
        }

        // "Wider" means "larger"
        static func < (lhs: SettingsView.AspectRatio, rhs: SettingsView.AspectRatio) -> Bool {
            (Double(lhs.width) / Double(lhs.height)) < (Double(rhs.width) / Double(rhs.height))
        }
    }

    struct Resolution: Equatable, Hashable, CustomStringConvertible {
        var width: Int
        var height: Int

        var aspectRatio: AspectRatio {
            AspectRatio(width: width, height: height)
        }

        var description: String {
            switch self {
            case Resolution(width: 3840, height: 2160):
                "4K"
            case _ where simplifyFraction(numerator: width, denominator: height) == simplifyFraction(numerator: 16, denominator: 9):
                "\(height)p"
            default:
                "\(width)x\(height)"
            }
        }
    }

    static let resolutionTable = [
        // 16:9
        Resolution(width: 1280, height: 720),
        Resolution(width: 1920, height: 1080),
        Resolution(width: 2560, height: 1440),
        Resolution(width: 3840, height: 2160),
        // 16:10
        Resolution(width: 1920, height: 1200),
        Resolution(width: 2560, height: 1600),
        // "21:9"
        Resolution(width: 2560, height: 1080),
        Resolution(width: 3440, height: 1440),
        // 32:9
        Resolution(width: 5120, height: 1440),
    ]

    static var resolutionsGroupedByType: [(AspectRatio, [Resolution])] {
        Dictionary(grouping: resolutionTable, by: \.aspectRatio).sorted { $0.key < $1.key }
    }

    static let framerateTable: [Int32] = [30, 60, 90, 120]

    static let bitrateTable: [Int32] = [
        5000, 10000, 30000, 50000, 75000, 100000, 120000, 200000,
        250000, 300000, 400000, 500000
    ]
}

// Functions to help with aspect ratio calculation
private func gcd<I: BinaryInteger>(_ a: I, _ b: I) -> I {
    var a = a
    var b = b
    while b != 0 {
        let temp = b
        b = a % b
        a = temp
    }
    return a
}

private func simplifyFraction<I: BinaryInteger>(numerator: I, denominator: I) -> (numerator: I, denominator: I) {
    let divisor = gcd(numerator, denominator)
    return (numerator / divisor, denominator / divisor)
}

#Preview {
    @Previewable @State var settings = TemporarySettings()
    return SettingsView(settings: $settings)
}
