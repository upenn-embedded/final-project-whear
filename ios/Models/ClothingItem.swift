import SwiftUI
import FirebaseFirestore

// MARK: - Enums

enum ClothingStatus: String, Codable, CaseIterable, Identifiable {
    case closet  = "Closet"
    case laundry = "Laundry"
    case missing = "Missing"
    case worn    = "Worn"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .closet:  return .statusCloset
        case .laundry: return .statusLaundry
        case .missing: return .statusMissing
        case .worn:    return .statusWorn
        }
    }

    var icon: String {
        switch self {
        case .closet:  return "tshirt"
        case .laundry: return "washer"
        case .missing: return "questionmark.circle"
        case .worn:    return "person.fill"
        }
    }
}

enum ClothingCategory: String, Codable, CaseIterable, Identifiable {
    case tops        = "Tops"
    case bottoms     = "Bottoms"
    case outerwear   = "Outerwear"
    case shoes       = "Shoes"
    case accessories = "Accessories"
    case dresses     = "Dresses"
    case activewear  = "Activewear"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tops:        return "tshirt"
        case .bottoms:     return "rectangle.fill"
        case .outerwear:   return "wind"
        case .shoes:       return "shoeprints.fill"
        case .accessories: return "bag.fill"
        case .dresses:     return "sparkles"
        case .activewear:  return "figure.run"
        }
    }
}

// MARK: - Model

struct ClothingItem: Identifiable, Codable, Equatable {
    var id: String        = UUID().uuidString
    var name: String
    var category: ClothingCategory
    var colorHex: String
    var status: ClothingStatus
    var tagId: String?
    var imageUrl: String?
    var lastSeen: Date?
    var wearCount: Int    = 0
    var dateAdded: Date   = Date()
    var brand: String?
    var notes: String?
    var isFavorite: Bool  = false

    var displayColor: Color { Color(hex: colorHex) ?? .gray }

    // Firestore helpers
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "id": id, "name": name,
            "category": category.rawValue,
            "colorHex": colorHex,
            "status": status.rawValue,
            "wearCount": wearCount,
            "dateAdded": Timestamp(date: dateAdded),
            "isFavorite": isFavorite
        ]
        if let t = tagId    { data["tagId"]    = t }
        if let u = imageUrl { data["imageUrl"] = u }
        if let l = lastSeen { data["lastSeen"] = Timestamp(date: l) }
        if let b = brand    { data["brand"]    = b }
        if let n = notes    { data["notes"]    = n }
        return data
    }

    static func from(_ doc: DocumentSnapshot) -> ClothingItem? {
        guard let d = doc.data() else { return nil }
        guard
            let name     = d["name"] as? String,
            let catRaw   = d["category"] as? String, let cat = ClothingCategory(rawValue: catRaw),
            let hex      = d["colorHex"] as? String,
            let statRaw  = d["status"] as? String,   let stat = ClothingStatus(rawValue: statRaw)
        else { return nil }

        var item        = ClothingItem(name: name, category: cat, colorHex: hex, status: stat)
        item.id         = doc.documentID
        item.tagId      = d["tagId"]    as? String
        item.imageUrl   = d["imageUrl"] as? String
        item.wearCount  = d["wearCount"] as? Int ?? 0
        item.brand      = d["brand"]    as? String
        item.notes      = d["notes"]    as? String
        item.isFavorite = d["isFavorite"] as? Bool ?? false
        if let ts = d["lastSeen"] as? Timestamp { item.lastSeen = ts.dateValue() }
        if let ts = d["dateAdded"] as? Timestamp { item.dateAdded = ts.dateValue() }
        return item
    }

    static func == (lhs: ClothingItem, rhs: ClothingItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - Mock data

extension ClothingItem {
    static let mockItems: [ClothingItem] = [
        ClothingItem(id: "1", name: "Camel Wool Coat",    category: .outerwear,   colorHex: "#C19A6B", status: .closet,  tagId: "A1F3", imageUrl: nil, lastSeen: Date(), wearCount: 8,  dateAdded: Date(), brand: "Arket"),
        ClothingItem(id: "2", name: "Black Tailored Trousers", category: .bottoms, colorHex: "#2C2C2C", status: .laundry, tagId: "B2D7", imageUrl: nil, lastSeen: Date(), wearCount: 15, dateAdded: Date(), brand: "COS"),
        ClothingItem(id: "3", name: "White Linen Shirt",  category: .tops,        colorHex: "#F5F0E8", status: .closet,  tagId: "C4A1", imageUrl: nil, lastSeen: Date(), wearCount: 12, dateAdded: Date(), brand: "Uniqlo"),
        ClothingItem(id: "4", name: "Blue Silk Blouse",   category: .tops,        colorHex: "#5B7FA6", status: .missing, tagId: "D5E2", imageUrl: nil, lastSeen: Date(), wearCount: 3,  dateAdded: Date(), brand: "Mango"),
        ClothingItem(id: "5", name: "Forest Blazer",      category: .outerwear,   colorHex: "#3D5A3E", status: .closet,  tagId: "E3F0", imageUrl: nil, lastSeen: Date(), wearCount: 6,  dateAdded: Date(), brand: "Zara"),
        ClothingItem(id: "6", name: "Burgundy Midi Dress",category: .dresses,     colorHex: "#6E2B3A", status: .closet,  tagId: "F1B8", imageUrl: nil, lastSeen: Date(), wearCount: 4,  dateAdded: Date(), brand: "& Other Stories"),
        ClothingItem(id: "7", name: "White Sneakers",     category: .shoes,       colorHex: "#FFFFFF", status: .closet,  tagId: "G9C2", imageUrl: nil, lastSeen: Date(), wearCount: 22, dateAdded: Date(), brand: "Adidas"),
        ClothingItem(id: "8", name: "Denim Jacket",       category: .outerwear,   colorHex: "#4A6FA5", status: .worn,    tagId: "H7D4", imageUrl: nil, lastSeen: Date(), wearCount: 9,  dateAdded: Date(), brand: "Levi's"),
    ]
}
