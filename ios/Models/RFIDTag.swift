import Foundation

struct RFIDTag: Identifiable, Codable {
    var id: String    // EPC code
    var rssi: Double?
    var lastSeen: Date
    var scanCount: Int = 1
}

struct RFIDInventoryResponse: Codable {
    var tags: [RFIDTag]
    var scanTime: Date
    var scanDuration: Double   // seconds
    var readerStatus: String
}

// Endpoint returned from ESP32 Wi-Fi bridge
// GET http://<device-ip>/inventory
// Returns JSON: { "tags": [...], "scanTime": "...", "scanDuration": 1.2, "readerStatus": "ok" }
