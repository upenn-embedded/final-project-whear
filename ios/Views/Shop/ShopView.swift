import SwiftUI

struct ShopView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var selectedReason: ShopReason? = nil

    private let shopItems = ShopItem.mockItems

    private var filteredItems: [ShopItem] {
        guard let r = selectedReason else { return shopItems }
        return shopItems.filter { $0.reason == r }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    navHeader
                    reasonFilter.padding(.bottom, 16)

                    if selectedReason == nil {
                        completeYourLook.padding(.bottom, 20)
                    }

                    shopGrid
                    Spacer(minLength: 90)
                }
            }
            .background(Color.whearBackground)
            .navigationBarHidden(true)
        }
    }

    // MARK: - Header

    private var navHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Discover")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundColor(.whearText)
                Text("Based on your wardrobe")
                    .font(.whearCaption)
                    .foregroundColor(.whearSubtext)
            }
            Spacer()
            Image(systemName: "bag")
                .font(.system(size: 20))
                .foregroundColor(.whearText)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Reason filter

    private var reasonFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selectedReason == nil) {
                    withAnimation { selectedReason = nil }
                }
                ForEach([ShopReason.completeLook, .similarItem, .trending, .filling], id: \.rawValue) { reason in
                    FilterChip(label: reason.rawValue, isSelected: selectedReason == reason) {
                        withAnimation { selectedReason = selectedReason == reason ? nil : reason }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Complete your look hero

    private var completeYourLook: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Complete Your Look")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(vm.items.prefix(3)) { wardrobeItem in
                        CompleteLookCard(
                            item: wardrobeItem,
                            suggestions: shopItems.filter { $0.pairsWith == wardrobeItem.name }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Shop grid

    private var shopGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: selectedReason?.rawValue ?? "All Picks")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(filteredItems) { item in
                    ShopItemCard(item: item)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Complete Look Card

private struct CompleteLookCard: View {
    let item: ClothingItem
    let suggestions: [ShopItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ItemImage(item: item, size: 28, cornerRadius: 6)
                Text("Pairs with \(item.name)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.whearText)
                    .lineLimit(1)
            }
            Text("\(suggestions.count) suggestions found")
                .font(.whearCaption)
                .foregroundColor(.whearSubtext)

            HStack(spacing: 8) {
                ForEach(suggestions.prefix(2)) { s in
                    VStack(spacing: 5) {
                        ShopItemThumbnail(item: s, size: 52)
                        Text(s.brand)
                            .font(.system(size: 9))
                            .foregroundColor(.whearSubtext)
                        Text(s.formattedPrice)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.whearText)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 180)
        .background(Color.whearBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Shop Item Card

struct ShopItemCard: View {
    let item: ShopItem
    @State private var isSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ShopItemThumbnail(item: item, size: nil)
                    .aspectRatio(1, contentMode: .fit)

                Text(item.reason.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    withAnimation(.spring(response: 0.2)) { isSaved.toggle() }
                } label: {
                    Image(systemName: isSaved ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundColor(isSaved ? .statusMissing : .white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.brand)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.whearSubtext)
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.whearText)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(item.formattedPrice)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.whearText)
                    if let rating = item.rating {
                        Spacer()
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.statusLaundry)
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 11))
                            .foregroundColor(.whearSubtext)
                    }
                }
            }

            Button { } label: {
                Text("Shop")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.whearPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color.whearBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Shop Item Thumbnail
// Shows the real image when imageUrl is set; falls back to the colour swatch.

private struct ShopItemThumbnail: View {
    let item: ShopItem
    /// Pass nil to let the view fill its parent (for the grid card hero).
    var size: CGFloat?

    var body: some View {
        if let urlString = item.imageUrl, let url = URL(string: urlString) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size != nil ? 8 : 12))
            } placeholder: {
                ZStack {
                    RoundedRectangle(cornerRadius: size != nil ? 8 : 12)
                        .fill(item.displayColor.opacity(0.35))
                        .frame(width: size, height: size)
                    ProgressView().scaleEffect(0.7).tint(.white)
                }
            } failure: {
                colorFallback
            }
        } else {
            colorFallback
        }
    }

    private var colorFallback: some View {
        RoundedRectangle(cornerRadius: size != nil ? 8 : 12)
            .fill(item.displayColor.opacity(0.8))
            .frame(width: size, height: size)
    }
}
