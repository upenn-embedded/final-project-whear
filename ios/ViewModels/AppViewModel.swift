import SwiftUI
import Combine
import FirebaseFirestore

@MainActor
final class AppViewModel: ObservableObject {

    @Published var items: [ClothingItem]      = ClothingItem.mockItems
    @Published var isLoading: Bool            = false
    @Published var alertCount: Int            = 0
    @Published var selectedTab: Int           = 0
    @Published var errorMessage: String?      = nil
    @Published private(set) var isReconciling: Bool = false


    // Unregistered tag state — auto-detected on scanner sync
    @Published var pendingRegistrationTagId: String?   = nil
    @Published var showMultipleUnregisteredAlert: Bool = false
    @Published var unregisteredTagIds: [String]        = []

    // Regular add-item sheet — triggered by FAB when no unregistered tags exist
    @Published var showRegularAddItem: Bool = false

    private var firestoreListener:  ListenerRegistration?
    private var scannerListener:    ListenerRegistration?
    private let firebase = FirebaseService.shared
    private let rfid     = RFIDService.shared

    // MARK: - Computed subsets

    var inCloset:  [ClothingItem] { items.filter { $0.status == .closet  } }
    var inLaundry: [ClothingItem] { items.filter { $0.status == .laundry } }
    var missing:   [ClothingItem] { items.filter { $0.status == .missing } }
    var worn:      [ClothingItem] { items.filter { $0.status == .worn    } }

    // MARK: - Init

    init() {
        alertCount = ClothingItem.mockItems.filter { $0.status == .missing }.count
        Task { await bootstrap() }
    }

    func bootstrap() async {
        do {
            try await firebase.signInAnonymouslyIfNeeded()
            startListeningToItems()
            startListeningToScanner()
            rfid.startPolling()
        } catch {
            errorMessage = "Setup error: \(error.localizedDescription)"
        }
    }

    // MARK: - Listeners

    func startListeningToItems() {
        firestoreListener = firebase.listenToItems { [weak self] newItems in
            guard let self else { return }
            // Skip Firestore snapshots that arrive while reconcile is in
            // progress — they carry pre-reconcile statuses and would undo
            // the local patch, causing Recent Activity / Missing Items to
            // show stale data while the stat cards already look correct.
            guard !self.isReconciling else { return }
            if !newItems.isEmpty { self.items = newItems }
            self.alertCount = newItems.filter { $0.status == .missing }.count
        }
    }

    func startListeningToScanner() {
        scannerListener = firebase.listenToScanner { [weak self] _ in
            guard let self else { return }
            Task { await self.runReconcile() }
        }
    }

    // MARK: - Reconciliation

   // func runReconcile() async {
     //   do {
     //       let result = try await firebase.reconcile()
    //        handleUnregistered(result.unregistered)
    //    } catch {
    //        errorMessage = "Sync error: \(error.localizedDescription)"
    //    }
   // }
    // MARK: - Reconciliation

    func runReconcile() async {
        isReconciling = true
        do {
            let result = try await firebase.reconcile()
            handleUnregistered(result.unregistered)

            // 1. Patch immediately so every section (stats, Recent Activity,
            //    Missing Items) updates in the same render pass.
            let inClosetSet = Set(result.inCloset)
            let missingSet  = Set(result.missing)
            items = items.map { item in
                guard let tagId = item.tagId else { return item }
                var updated = item
                if inClosetSet.contains(tagId)      { updated.status = .closet  }
                else if missingSet.contains(tagId)  { updated.status = .missing }
                return updated
            }
            alertCount = items.filter { $0.status == .missing }.count

            // 2. Fetch the freshly-committed server state so the listener's
            //    next snapshot won't be treated as newer than what we know.
            if let fresh = try? await firebase.fetchItems(), !fresh.isEmpty {
                items = fresh
                alertCount = fresh.filter { $0.status == .missing }.count
            }
        } catch {
            errorMessage = "Sync error: \(error.localizedDescription)"
        }
        isReconciling = false
    }

    private func handleUnregistered(_ tagIds: [String]) {
        unregisteredTagIds = tagIds
        pendingRegistrationTagId = nil
        showMultipleUnregisteredAlert = false

        switch tagIds.count {
        case 0:
            break
        case 1:
            pendingRegistrationTagId = tagIds[0]
        default:
            showMultipleUnregisteredAlert = true
        }
    }

    // MARK: - FAB tap logic
    //
    // Priority order:
    //   1. Exactly one unregistered tag in scanner → open AddItemView pre-filled with that tag
    //   2. Multiple unregistered tags             → show the multi-tag alert
    //   3. No unregistered tags                   → open a blank AddItemView
    //
    // We re-reconcile first so the state is always fresh at the moment the
    // user taps, not stale from the last background poll.

    func handleAddButtonTap() async {
        // Run a fresh reconcile so unregisteredTagIds reflects the current scanner
        await runReconcile()

        switch unregisteredTagIds.count {
        case 0:
            // Nothing unregistered — open the regular blank add sheet
            showRegularAddItem = true
        case 1:
            // pendingRegistrationTagId was already set by runReconcile → sheet auto-opens
            break
        default:
            // showMultipleUnregisteredAlert was already set by runReconcile → alert auto-shows
            break
        }
    }

    // MARK: - RFID manual refresh

    func refreshFromRFID() async {
        // Reconcile against current Firestore scanner state immediately —
        // no RFID round-trip needed for the status update.
        await runReconcile()
        // If the reader is live, also push a fresh scan so the next
        // reconcile has up-to-date tag data.
        if rfid.isConnected {
            await rfid.triggerManualScan()
            await runReconcile()
        }
    }

    // MARK: - Item mutations

    func addItem(_ item: ClothingItem, image: UIImage?) async {
        var newItem = item
        isLoading = true
        defer { isLoading = false }
        do {
            if let img = image {
                newItem.imageUrl = try await firebase.uploadImage(img, for: newItem.id)
            }
            try await firebase.saveItem(newItem)
            if newItem.tagId != nil { await runReconcile() }
        } catch {
            items.insert(newItem, at: 0)
        }
    }

    func updateStatus(_ item: ClothingItem, status: ClothingStatus) async {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].status = status
        try? await firebase.updateItemStatus(item, status: status)
    }

    func deleteItem(_ item: ClothingItem) async {
        items.removeAll { $0.id == item.id }
        do {
            try await firebase.deleteItem(item)
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
            if let fresh = try? await firebase.fetchItems() { items = fresh }
        }
    }

    // MARK: - Tag registration flow

    func registerPendingTag(for item: ClothingItem, image: UIImage?) async {
        await addItem(item, image: image)
        pendingRegistrationTagId = nil
    }

    func dismissPendingTag() {
        pendingRegistrationTagId = nil
    }

    deinit {
        firestoreListener?.remove()
        scannerListener?.remove()
    }
}
