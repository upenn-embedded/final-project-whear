import SwiftUI

struct OutfitsView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var selectedOccasion: Occasion = .dateNight
    @State private var selectedSegment: Int = 0         // 0=Ideas, 1=Favorites, 2=Worn
    @State private var showOutfitDetail: Outfit? = nil

    private let outfits = Outfit.mockOutfits

    private var filteredOutfits: [Outfit] {
        switch selectedSegment {
        case 1: return outfits.filter { $0.isFavorite }
        case 2: return outfits.sorted { $0.wearCount > $1.wearCount }
        default: return outfits.filter { $0.occasion == selectedOccasion }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // Header
                    navHeader

                    // Segment picker
                    segmentPicker
                        .padding(.top, 4)
                        .padding(.bottom, 16)

                    if selectedSegment == 0 {
                        // Occasion filter + AI recommendations
                        occasionFilter
                        weatherCard
                            .padding(.bottom, 8)
                        outfitCards
                    } else if selectedSegment == 1 {
                        favoriteBoards
                    } else {
                        mostWornList
                    }

                    Spacer(minLength: 90)
                }
            }
            .background(Color.whearBackground)
            .navigationBarHidden(true)
            .sheet(item: $showOutfitDetail) { outfit in
                OutfitDetailSheet(outfit: outfit)
            }
        }
    }

    // MARK: - Header

    private var navHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Outfits")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundColor(.whearText)
                Text("Based on your wardrobe")
                    .font(.whearCaption)
                    .foregroundColor(.whearSubtext)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Segment

    private var segmentPicker: some View {
        HStack(spacing: 0) {
            ForEach(["Ideas", "Favorites", "Most Worn"].indices, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.3)) { selectedSegment = i }
                } label: {
                    Text(["Ideas", "Favorites", "Most Worn"][i])
                        .font(.system(size: 14, weight: selectedSegment == i ? .semibold : .regular))
                        .foregroundColor(selectedSegment == i ? .whearText : .whearSubtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedSegment == i ?
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color.whearBackground)
                                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2) : nil
                        )
                }
            }
        }
        .padding(4)
        .background(Color.whearSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Occasion filter

    private var occasionFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Occasion.allCases) { occ in
                    Button {
                        withAnimation(.spring(response: 0.25)) { selectedOccasion = occ }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: occ.icon)
                                .font(.system(size: 11))
                            Text(occ.rawValue)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(selectedOccasion == occ ? .white : .whearText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selectedOccasion == occ ? Color.whearPrimary : Color.whearSurface)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 14)
    }

    // MARK: - Weather

    private var weatherCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 22))
                .foregroundColor(.statusLaundry)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tonight · 14°C")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.whearText)
                Text("Partly cloudy — a light layer recommended")
                    .font(.whearCaption)
                    .foregroundColor(.whearSubtext)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.statusLaundry.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Outfit cards

    private var outfitCards: some View {
        VStack(spacing: 14) {
            ForEach(filteredOutfits) { outfit in
                OutfitCard(outfit: outfit) {
                    showOutfitDetail = outfit
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Favorites boards

    private var favoriteBoards: some View {
        VStack(spacing: 14) {
            let favs = outfits.filter { $0.isFavorite }
            if favs.isEmpty {
                EmptyStateView(icon: "heart", title: "No favorites yet", subtitle: "Save outfits you love to see them here")
                    .padding(.top, 40)
            } else {
                ForEach(favs) { outfit in
                    OutfitCard(outfit: outfit) { showOutfitDetail = outfit }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Most worn

    private var mostWornList: some View {
        VStack(spacing: 14) {
            ForEach(outfits.sorted { $0.wearCount > $1.wearCount }) { outfit in
                OutfitCard(outfit: outfit) { showOutfitDetail = outfit }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Outfit Card

struct OutfitCard: View {
    let outfit: Outfit
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(outfit.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.whearText)
                            if outfit.isAIPick {
                                Text("AI Pick")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.whearPrimary)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(outfit.occasion.rawValue)
                            .font(.whearCaption)
                            .foregroundColor(.whearSubtext)
                    }
                    Spacer()
                    if let score = outfit.matchScore {
                        VStack(spacing: 1) {
                            Text("\(score)%")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.whearPrimary)
                            Text("match")
                                .font(.system(size: 10))
                                .foregroundColor(.whearSubtext)
                        }
                    }
                }

                // Color grid
                OutfitColorGrid(items: outfit.items)

                // Actions
                HStack(spacing: 10) {
                    Button {
                        // Use today
                    } label: {
                        Text("Use Today")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 9)
                            .background(Color.whearPrimary)
                            .clipShape(Capsule())
                    }
                    Button {
                        // Save
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: outfit.isFavorite ? "heart.fill" : "heart")
                            Text("Save")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.whearText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.whearSurface)
                        .clipShape(Capsule())
                    }
                    Spacer()
                    if outfit.wearCount > 0 {
                        Text("Worn \(outfit.wearCount)×")
                            .font(.whearCaption)
                            .foregroundColor(.whearSubtext)
                    }
                }
            }
            .padding(16)
            .background(Color.whearBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Outfit Detail Sheet

struct OutfitDetailSheet: View {
    let outfit: Outfit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Big color grid
                    let cols = [GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(outfit.items) { item in
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(item.displayColor)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.07), lineWidth: 0.5))
                                Text(item.label)
                                    .font(.system(size: 13))
                                    .foregroundColor(.whearText)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Occasion + match
                    HStack {
                        Label(outfit.occasion.rawValue, systemImage: outfit.occasion.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.whearText)
                        Spacer()
                        if let score = outfit.matchScore {
                            Text("\(score)% wardrobe match")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.whearPrimary)
                        }
                    }
                    .padding(.horizontal)

                    WhearButton(title: "Wear This Today", icon: "checkmark.circle") {}
                        .padding(.horizontal)
                }
                .padding(.top, 8)
            }
            .background(Color.whearBackground)
            .navigationTitle(outfit.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.whearPrimary)
                }
            }
        }
    }
}
