import Foundation
import Combine

@MainActor
final class RFIDService: ObservableObject {

    static let shared = RFIDService()

    @Published var deviceBaseURL: String = UserDefaults.standard.string(forKey: "rfid_base_url") ?? ""
    @Published var isConnected: Bool     = false
    @Published var isScanning: Bool      = false
    @Published var lastScan: Date?
    @Published var detectedTags: [RFIDTag] = []
    @Published var errorMessage: String?

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 10   // SRS-01: 10-second cycle
    private let session = URLSession.shared

    // MARK: - URL persistence

    func setDeviceURL(_ url: String) {
        deviceBaseURL = url
        UserDefaults.standard.set(url, forKey: "rfid_base_url")
    }

    // MARK: - Polling

    func startPolling() {
        guard !deviceBaseURL.isEmpty else { return }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.fetchInventory() }
        }
        Task { await fetchInventory() }   // immediate first scan
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isScanning = false
    }

    // MARK: - Fetch from ESP32 and push to Firestore scanner collection

    func fetchInventory() async {
        guard !deviceBaseURL.isEmpty else { return }
        isScanning = true
        errorMessage = nil

        let urlString = "\(deviceBaseURL)/inventory"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid device URL"
            isScanning = false
            return
        }

        do {
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "GET"
            let (data, response) = try await session.data(for: request)

            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                isConnected = false
                errorMessage = "Reader returned unexpected response"
                isScanning = false
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let inventory = try decoder.decode(RFIDInventoryResponse.self, from: data)

            detectedTags = inventory.tags
            lastScan     = inventory.scanTime
            isConnected  = true

            // Write current tag IDs to Firestore scanner collection.
            // AppViewModel's scanner listener will pick up the change and reconcile.
            let tagIds = inventory.tags.map { $0.id }
            try await FirebaseService.shared.updateScannerCollection(tagIds: tagIds)

        } catch {
            isConnected  = false
            errorMessage = error.localizedDescription
        }

        isScanning = false
    }

    // MARK: - Manual scan trigger

    func triggerManualScan() async {
        guard !deviceBaseURL.isEmpty else { return }
        let urlString = "\(deviceBaseURL)/scan"
        if let url = URL(string: urlString) {
            var req = URLRequest(url: url, timeoutInterval: 5)
            req.httpMethod = "POST"
            try? await session.data(for: req)
        }
        await fetchInventory()
    }

    // MARK: - Tag registration (notifies ESP32 of the new association)

    func registerTag(_ tagId: String, for itemId: String) async throws {
        if !deviceBaseURL.isEmpty, let url = URL(string: "\(deviceBaseURL)/register") {
            var req = URLRequest(url: url, timeoutInterval: 5)
            req.httpMethod = "POST"
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["tagId": tagId, "itemId": itemId])
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            try? await session.data(for: req)
        }
        try await FirebaseService.shared.associateTag(itemId: itemId, tagId: tagId)
    }
}
