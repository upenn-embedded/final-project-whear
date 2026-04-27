import SwiftUI

// MARK: - Item Image (cached, with color swatch fallback)

struct ItemImage: View {
    let item: ClothingItem
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let urlString = item.imageUrl, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                } placeholder: {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(item.displayColor.opacity(0.35))
                            .frame(width: size, height: size)
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    }
                } failure: {
                    ColorSwatch(color: item.displayColor, size: size, cornerRadius: cornerRadius)
                }
            } else {
                ColorSwatch(color: item.displayColor, size: size, cornerRadius: cornerRadius)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: ClothingStatus
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            if !compact {
                Text(status.rawValue)
                    .font(.whearCaption)
                    .foregroundColor(status.color)
            }
        }
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(status.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Color Swatch

struct ColorSwatch: View {
    let color: Color
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )
    }
}

// MARK: - Card

struct WhearCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Color.whearBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.whearText)
            Spacer()
            if let action {
                Button(action ?? "", action: onAction ?? {})
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.whearPrimary)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Primary Button

struct WhearButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    if let icon { Image(systemName: icon) }
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.whearPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isLoading)
    }
}

// MARK: - RFID Connection Badge

struct RFIDStatusBadge: View {
    @ObservedObject var rfid = RFIDService.shared

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(rfid.isConnected ? Color.statusCloset : Color.whearSubtext)
                .frame(width: 7, height: 7)
                .overlay(
                    rfid.isScanning ?
                    Circle()
                        .stroke(Color.statusCloset.opacity(0.4), lineWidth: 2)
                        .scaleEffect(rfid.isScanning ? 1.8 : 1)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: rfid.isScanning)
                    : nil
                )
            Text(rfid.isConnected ? "RFID Live" : "Offline")
                .font(.whearCaption)
                .foregroundColor(rfid.isConnected ? .statusCloset : .whearSubtext)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((rfid.isConnected ? Color.statusCloset : Color.whearSubtext).opacity(0.10))
        .clipShape(Capsule())
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.whearSecondary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.whearText)
            Text(subtitle)
                .font(.whearBody)
                .foregroundColor(.whearSubtext)
                .multilineTextAlignment(.center)
            if let action, let onAction {
                Button(action, action: onAction)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.whearPrimary)
                    .padding(.top, 4)
            }
        }
        .padding(32)
    }
}

// MARK: - Outfit Color Grid

struct OutfitColorGrid: View {
    let items: [OutfitItem]
    var size: CGFloat = 52

    private let columns = [GridItem(.adaptive(minimum: 52))]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items) { item in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(item.displayColor)
                        .frame(width: size, height: size)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.07), lineWidth: 0.5)
                        )
                    Text(item.label)
                        .font(.system(size: 9))
                        .foregroundColor(.whearSubtext)
                        .lineLimit(1)
                }
            }
        }
    }
}
