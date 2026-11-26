//
//

import SwiftUI

struct DashboardPalette {
    let primary: Color

    static let hero = DashboardPalette(primary: Color(red: 0.31, green: 0.26, blue: 0.78))
    static let hostOnline = DashboardPalette(primary: Color(red: 0.19, green: 0.60, blue: 0.92))
    static let hostOffline = DashboardPalette(primary: Color(red: 0.34, green: 0.39, blue: 0.50))
    static let action = DashboardPalette(primary: Color(red: 0.10, green: 0.63, blue: 0.58))
    static let caution = DashboardPalette(primary: Color(red: 0.87, green: 0.42, blue: 0.22))
    static let app = DashboardPalette(primary: Color(red: 0.73, green: 0.30, blue: 0.58))
}

enum DashboardLayout {
    static func columns(for width: CGFloat, targetTileWidth: CGFloat = 300) -> [GridItem] {
        let contentWidth = max(width - 56, 240)
        let columnCount = max(Int(contentWidth / targetTileWidth), 1)
        return Array(
            repeating: GridItem(.flexible(minimum: 220, maximum: 420), spacing: 20, alignment: .top),
            count: columnCount
        )
    }
}

struct DashboardSection<Content: View>: View {
    let title: String
    let subtitle: String
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: DashboardLayout.columns(for: width), alignment: .leading, spacing: 20) {
                content
            }
        }
    }
}

struct DashboardHeroCard<Content: View>: View {
    let title: String
    let description: String
    let palette: DashboardPalette
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))

            content

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(palette.primary)
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
}

struct DashboardSummaryPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.14), in: Capsule())
    }
}

struct DashboardTile<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let palette: DashboardPalette
    @ViewBuilder let content: Content

    private let tileShape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    private let tileHeight: CGFloat = 196

    var body: some View {
        ZStack(alignment: .topLeading) {
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
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .center) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tint(.white)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .bottomLeading)
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
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: palette.primary.opacity(0.24), radius: 24, x: 0, y: 16)
        .hoverEffect(.highlight)
    }
}
