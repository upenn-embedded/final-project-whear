import SwiftUI

extension Color {
    // Brand palette — white base, warm terracotta primary
    static let whearPrimary    = Color(hex: "#C4622D")!   // terracotta
    static let whearSecondary  = Color(hex: "#E8DDD0")!   // warm sand
    static let whearAccent     = Color(hex: "#3D7A5E")!   // forest green
    static let whearBackground = Color.white
    static let whearSurface    = Color(hex: "#F7F5F2")!   // off-white surface
    static let whearBorder     = Color(hex: "#EBEBEB")!
    static let whearText       = Color(hex: "#1A1A1A")!
    static let whearSubtext    = Color(hex: "#888888")!

    // Status colours
    static let statusCloset    = Color(hex: "#3D7A5E")!
    static let statusLaundry   = Color(hex: "#E09B3D")!
    static let statusMissing   = Color(hex: "#C0392B")!
    static let statusWorn      = Color(hex: "#5B72C0")!

    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard h.count == 6 || h.count == 8 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&rgb) else { return nil }
        let len = h.count
        let r = CGFloat((rgb >> (len == 8 ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((rgb >> (len == 8 ? 16 :  8)) & 0xFF) / 255
        let b = CGFloat((rgb >> (len == 8 ?  8 :  0)) & 0xFF) / 255
        let a = len == 8 ? CGFloat(rgb & 0xFF) / 255 : 1.0
        self.init(red: r, green: g, blue: b, opacity: a)
    }

    func toHex() -> String {
        let c = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}

extension Font {
    static let whearTitle    = Font.system(size: 28, weight: .bold, design: .serif)
    static let whearHeading  = Font.system(size: 20, weight: .semibold, design: .default)
    static let whearBody     = Font.system(size: 15, weight: .regular, design: .default)
    static let whearCaption  = Font.system(size: 12, weight: .medium, design: .default)
    static let whearMono     = Font.system(size: 11, weight: .medium, design: .monospaced)
}
