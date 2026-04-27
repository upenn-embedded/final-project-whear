import SwiftUI

// MARK: - Occasion

enum Occasion: String, CaseIterable, Identifiable {
    case dateNight = "Date Night"
    case work      = "Work"
    case casual    = "Casual"
    case formal    = "Formal"
    case weekend   = "Weekend"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dateNight: return "heart.fill"
        case .work:      return "briefcase.fill"
        case .casual:    return "leaf.fill"
        case .formal:    return "star.fill"
        case .weekend:   return "sun.max.fill"
        }
    }
}

// MARK: - Outfit

struct OutfitItem: Identifiable {
    var id: String
    var colorHex: String
    var label: String
    var displayColor: Color { Color(hex: colorHex) ?? .gray }
}

struct Outfit: Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var occasion: Occasion
    var items: [OutfitItem]
    var matchScore: Int?           // 0–100 AI match %
    var isAIPick: Bool  = false
    var isFavorite: Bool = false
    var wearCount: Int  = 0
    var lastWorn: Date?
    var imageUrl: String?
}

extension Outfit {
    static let mockOutfits: [Outfit] = [
        Outfit(
            id: "o1", name: "Evening Classic", occasion: .dateNight,
            items: [
                OutfitItem(id: "i1", colorHex: "#F5F0E8", label: "White Linen Shirt"),
                OutfitItem(id: "i2", colorHex: "#2C2C2C", label: "Black Trousers"),
                OutfitItem(id: "i3", colorHex: "#C19A6B", label: "Camel Coat"),
                OutfitItem(id: "i4", colorHex: "#1A1A1A", label: "Chelsea Boots"),
            ],
            matchScore: nil, isAIPick: true, isFavorite: true, wearCount: 5,
            lastWorn: Calendar.current.date(byAdding: .day, value: -3, to: Date())
        ),
        Outfit(
            id: "o2", name: "Chic Minimal", occasion: .dateNight,
            items: [
                OutfitItem(id: "i5", colorHex: "#3D5A3E", label: "Forest Blazer"),
                OutfitItem(id: "i6", colorHex: "#888888", label: "Grey Trousers"),
                OutfitItem(id: "i7", colorHex: "#C4622D", label: "Terracotta Bag"),
            ],
            matchScore: 86, isAIPick: false, isFavorite: false, wearCount: 2,
            lastWorn: Calendar.current.date(byAdding: .day, value: -10, to: Date())
        ),
        Outfit(
            id: "o3", name: "Business Ready", occasion: .work,
            items: [
                OutfitItem(id: "i8",  colorHex: "#F5F0E8", label: "White Shirt"),
                OutfitItem(id: "i9",  colorHex: "#3D5A3E", label: "Green Blazer"),
                OutfitItem(id: "i10", colorHex: "#2C2C2C", label: "Black Trousers"),
            ],
            matchScore: 92, isAIPick: true, isFavorite: false, wearCount: 7,
            lastWorn: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        ),
        Outfit(
            id: "o4", name: "Weekend Ease", occasion: .casual,
            items: [
                OutfitItem(id: "i11", colorHex: "#4A6FA5", label: "Denim Jacket"),
                OutfitItem(id: "i12", colorHex: "#FFFFFF", label: "White Tee"),
                OutfitItem(id: "i13", colorHex: "#ECECEC", label: "Light Jeans"),
                OutfitItem(id: "i14", colorHex: "#FFFFFF", label: "White Sneakers"),
            ],
            matchScore: 78, isAIPick: false, isFavorite: true, wearCount: 12,
            lastWorn: Calendar.current.date(byAdding: .day, value: -5, to: Date())
        ),
    ]
}

// MARK: - ShopItem

enum ShopReason: String {
    case completeLook  = "Complete Look"
    case similarItem   = "Similar Item"
    case trending      = "Trending"
    case filling       = "Fills a Gap"
}

struct ShopItem: Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var brand: String
    var price: Double
    var colorHex: String
    var reason: ShopReason
    var pairsWith: String?    // name of wardrobe item it pairs with
    var imageUrl: String?
    var rating: Double?
    var reviewCount: Int?
    var url: String?

    var displayColor: Color { Color(hex: colorHex) ?? .gray }
    var formattedPrice: String { String(format: "$%.0f", price) }
}

extension ShopItem {
    static let mockItems: [ShopItem] = [
        ShopItem(id: "s1", name: "Linen Shirt",      brand: "Arket",         price: 89,  colorHex: "#D4C5B0", reason: .completeLook, pairsWith: "Black Trousers",  rating: 4.5, reviewCount: 38),
        ShopItem(id: "s2", name: "Merino Knit",      brand: "COS",           price: 145, colorHex: "#3D5A3E", reason: .completeLook, pairsWith: "Black Trousers",  rating: 4.8, reviewCount: 71),
        ShopItem(id: "s3", name: "Leather Belt",     brand: "& Other Stories", price: 55, colorHex: "#4A3728", reason: .filling,     pairsWith: nil,               rating: 4.3, reviewCount: 22),
        ShopItem(id: "s4", name: "Scarf Coat",       brand: "Toteme",        price: 320, colorHex: "#C19A6B", reason: .trending,    pairsWith: nil,               rating: 4.9, reviewCount: 105),
        ShopItem(id: "s5", name: "Wide-Leg Trousers",brand: "Arket",         price: 110, colorHex: "#888080", reason: .similarItem, pairsWith: "Black Trousers",  rating: 4.4, reviewCount: 49),
        ShopItem(id: "s6", name: "Silk Midi Skirt",  brand: "Mango",         price: 79,  colorHex: "#6E2B3A", reason: .completeLook, pairsWith: "White Linen Shirt", rating: 4.2, reviewCount: 34),
        ShopItem(id: "s7", name: "Ankle Boots",      brand: "COS",           price: 195, colorHex: "#2C2C2C", reason: .filling,     pairsWith: nil,               rating: 4.7, reviewCount: 88),
        ShopItem(id: "s8", name: "Oversized Blazer", brand: "Zara",          price: 89,  colorHex: "#C4C4B0", reason: .trending,    pairsWith: nil,               rating: 4.1, reviewCount: 67),
    ]
}
