import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let item: ClothingItem

    @State private var showEditStatus = false
    @State private var showEdit = false
    @State private var localItem: ClothingItem

    init(item: ClothingItem) {
        self.item = item
        _localItem = State(initialValue: item)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    heroSection

                    VStack(alignment: .leading, spacing: 24) {
                        headerInfo
                        statusRow
                        statsRow
                        metadataSection

                        if localItem.tagId != nil {
                            rfidSection
                        }

                        actionButtons

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                }
            }
            .background(Color.whearBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.whearText)
                            .frame(width: 30, height: 30)
                            .background(Color.whearSurface)
                            .clipShape(Circle())
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 16) {
                        Button { showEdit = true } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 17))
                                .foregroundColor(.whearText)
                        }
                        Button {
                            Task {
                                var updated = localItem
                                updated.isFavorite.toggle()
                                localItem = updated
                                await vm.addItem(updated, image: nil)
                            }
                        } label: {
                            Image(systemName: localItem.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 18))
                                .foregroundColor(localItem.isFavorite ? .statusMissing : .whearText)
                        }
                    }
                }
            }
            .confirmationDialog("Update Status", isPresented: $showEditStatus) {
                ForEach(ClothingStatus.allCases) { status in
                    Button(status.rawValue) {
                        Task { await vm.updateStatus(localItem, status: status) }
                        localItem.status = status
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showEdit) {
                EditItemView(item: localItem) { updated in
                    localItem = updated
                }
                .environmentObject(vm)
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            // Background tint
            Rectangle()
                .fill(localItem.displayColor.opacity(0.15))
                .frame(height: 260)

            if let urlString = localItem.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                            .clipped()
                    case .failure:
                        fallbackHero
                    case .empty:
                        ZStack {
                            localItem.displayColor.opacity(0.15)
                            ProgressView()
                                .tint(.whearPrimary)
                        }
                        .frame(height: 260)
                    @unknown default:
                        fallbackHero
                    }
                }
            } else {
                fallbackHero
            }
        }
    }

    private var fallbackHero: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 20)
                .fill(localItem.displayColor)
                .frame(width: 120, height: 120)
                .shadow(color: localItem.displayColor.opacity(0.4), radius: 20, x: 0, y: 8)
        }
    }

    // MARK: - Header

    private var headerInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localItem.name)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundColor(.whearText)
            if let brand = localItem.brand {
                Text(brand)
                    .font(.system(size: 15))
                    .foregroundColor(.whearSubtext)
            }
        }
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack {
            Text("Status")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.whearSubtext)
            Spacer()
            Button { showEditStatus = true } label: {
                HStack(spacing: 6) {
                    StatusBadge(status: localItem.status)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(.whearSubtext)
                }
            }
        }
        .padding(14)
        .background(Color.whearSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatPill(value: "\(localItem.wearCount)", label: "Times Worn")
            StatPill(value: localItem.category.rawValue, label: "Category")
            if let last = localItem.lastSeen {
                StatPill(value: last.formatted(.dateTime.day().month()), label: "Last Seen")
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(spacing: 0) {
            MetaRow(label: "Category",   value: localItem.category.rawValue)
            Divider().padding(.leading, 16)
            MetaRow(label: "Added",      value: localItem.dateAdded.formatted(.dateTime.day().month().year()))
            if let notes = localItem.notes, !notes.isEmpty {
                Divider().padding(.leading, 16)
                MetaRow(label: "Notes", value: notes)
            }
        }
        .background(Color.whearBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 1)
    }

    // MARK: - RFID

    private var rfidSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.fill")
                .font(.system(size: 16))
                .foregroundColor(.whearPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("RFID Tag Registered")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.whearText)
                Text("Tag #\(localItem.tagId!)")
                    .font(.whearMono)
                    .foregroundColor(.whearSubtext)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.statusCloset)
        }
        .padding(14)
        .background(Color.whearPrimary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await vm.updateStatus(localItem, status: .laundry) }
                localItem.status = .laundry
            } label: {
                Label("Mark as Laundry", systemImage: "washer")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.statusLaundry)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.statusLaundry.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button(role: .destructive) {
                Task {
                    await vm.deleteItem(localItem)
                    dismiss()
                }
            } label: {
                Label("Remove from Closet", systemImage: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.statusMissing.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Small components

private struct StatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.whearText)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.whearSubtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.whearSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MetaRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.whearSubtext)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(.whearText)
            Spacer()
        }
        .padding(14)
    }
}
