import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

// MARK: - Reconcile result

struct ReconcileResult {
    var inCloset: [String]        // tagIds now confirmed in closet
    var missing: [String]         // tagIds registered to an item but absent from scanner
    var unregistered: [String]    // tagIds in scanner with no matching item
}

@MainActor
final class FirebaseService {

    static let shared = FirebaseService()

    private let db      = Firestore.firestore()
    private let storage = Storage.storage()

    // Flat top-level collections (no users nesting)
    private var itemsCollection:   CollectionReference { db.collection("items")   }
    private var scannerCollection: CollectionReference { db.collection("scanner") }

    // MARK: - Auth (anonymous, kept for Storage security rules)

    func signInAnonymouslyIfNeeded() async throws {
        if Auth.auth().currentUser == nil {
            try await Auth.auth().signInAnonymously()
        }
    }

    // MARK: - Items CRUD

    func fetchItems() async throws -> [ClothingItem] {
        let snapshot = try await itemsCollection
            .order(by: "dateAdded", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { ClothingItem.from($0) }
    }

    func saveItem(_ item: ClothingItem) async throws {
        try await itemsCollection.document(item.id).setData(item.firestoreData)
    }

    func updateItemStatus(_ item: ClothingItem, status: ClothingStatus) async throws {
        try await itemsCollection.document(item.id).updateData(["status": status.rawValue])
    }

    func deleteItem(_ item: ClothingItem) async throws {
        try await itemsCollection.document(item.id).delete()
        if let url = item.imageUrl {
            let ref = storage.reference(forURL: url)
            try? await ref.delete()
        }
    }

    func associateTag(itemId: String, tagId: String) async throws {
        try await itemsCollection.document(itemId).updateData([
            "tagId":    tagId,
            "lastSeen": Timestamp(date: Date())
        ])
    }

    // MARK: - Real-time listeners

    /// Listens to the items collection for UI updates.
    func listenToItems(onChange: @escaping ([ClothingItem]) -> Void) -> ListenerRegistration {
        itemsCollection
            .order(by: "dateAdded", descending: true)
            .addSnapshotListener { snapshot, _ in
                guard let snap = snapshot else { return }
                let items = snap.documents.compactMap { ClothingItem.from($0) }
                DispatchQueue.main.async { onChange(items) }
            }
    }

    /// Listens to the scanner collection. Returns tag IDs currently detected.
    func listenToScanner(onChange: @escaping ([String]) -> Void) -> ListenerRegistration {
        scannerCollection.addSnapshotListener { snapshot, _ in
            guard let snap = snapshot else { return }
            let tagIds = snap.documents.compactMap { $0.data()["id"] as? String }
            DispatchQueue.main.async { onChange(tagIds) }
        }
    }

    // MARK: - Scanner collection management

    /// Replaces the scanner collection with the latest tags reported by the ESP32.
    /// Each document: { id: "<tagId>" }
    func updateScannerCollection(tagIds: [String]) async throws {
        // Delete all existing scanner docs
        let existing = try await scannerCollection.getDocuments()
        let batch = db.batch()
        for doc in existing.documents {
            batch.deleteDocument(doc.reference)
        }
        // Write current detected tags
        for tagId in tagIds {
            let ref = scannerCollection.document()   // auto-ID, matching your console structure
            batch.setData(["id": tagId], forDocument: ref)
        }
        try await batch.commit()
    }

    // MARK: - Reconciliation

    /// Compares scanner collection against items collection and:
    ///   - Marks items whose tagId IS in scanner → Closet
    ///   - Marks items whose tagId is NOT in scanner → Missing
    ///   - Returns scanner tagIds that have no matching item (unregistered)
    @discardableResult
    func reconcile() async throws -> ReconcileResult {
        async let itemsSnap   = itemsCollection.getDocuments()
        async let scannerSnap = scannerCollection.getDocuments()

        let (iSnap, sSnap) = try await (itemsSnap, scannerSnap)

        let items        = iSnap.documents.compactMap { ClothingItem.from($0) }
        let scannerTagIds = Set(sSnap.documents.compactMap { $0.data()["id"] as? String })

        // Items that have a tagId
        let taggedItems = items.filter { $0.tagId != nil }

        let inClosetTagIds  = taggedItems.filter {  scannerTagIds.contains($0.tagId!) }.map { $0.tagId! }
        let missingTagIds   = taggedItems.filter { !scannerTagIds.contains($0.tagId!) }.map { $0.tagId! }
        let registeredTagIds = Set(taggedItems.compactMap { $0.tagId })
        let unregistered    = scannerTagIds.subtracting(registeredTagIds).sorted()

        // Batch-update statuses
        let batch    = db.batch()
        let now      = Timestamp(date: Date())

        for item in taggedItems {
            guard let tagId = item.tagId else { continue }
            let newStatus: ClothingStatus = scannerTagIds.contains(tagId) ? .closet : .missing
            if item.status != newStatus {
                batch.updateData(
                    ["status": newStatus.rawValue, "lastSeen": now],
                    forDocument: itemsCollection.document(item.id)
                )
            }
        }

        try await batch.commit()

        return ReconcileResult(
            inCloset:     inClosetTagIds,
            missing:      missingTagIds,
            unregistered: unregistered
        )
    }

    // MARK: - Image Upload

    func uploadImage(_ image: UIImage, for itemId: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "Whear", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Image compression failed"])
        }
        // Storage path uses anonymous UID so rules still apply
        let uid = Auth.auth().currentUser?.uid ?? "anon"
        let ref = storage.reference().child("items/\(uid)/\(itemId).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        let _ = try await ref.putDataAsync(data, metadata: meta)
        return try await ref.downloadURL().absoluteString
    }
}
