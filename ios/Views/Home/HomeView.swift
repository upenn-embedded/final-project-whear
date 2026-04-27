import SwiftUI

struct HomeView: View {
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject private var rfid = RFIDService.shared
    @State private var showSettings = false

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    headerSection
                    statsSection
                    rfidStatusCard

                    recentActivity

                    if !vm.missing.isEmpty {
                        missingSection
                    }

                    mostWorn

                    Spacer(minLength: 90)
                }
                .padding(.top, 8)
            }
            .refreshable { await vm.refreshFromRFID() }   // ← add this
            .background(Color.whearBackground)
            .navigationBarHidden(true)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.whearSubtext)
                Text("Your Closet")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundColor(.whearText)
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundColor(.whearText)
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: - Stats

    private var statsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                StatCard(value: "\(vm.items.count)", label: "Total Items",  color: .whearText,     icon: "tshirt.fill")
                StatCard(value: "\(vm.inCloset.count)",  label: "In Closet",   color: .statusCloset,  icon: "house.fill")
                StatCard(value: "\(vm.inLaundry.count)", label: "Laundry",     color: .statusLaundry, icon: "washer.fill")
                StatCard(value: "\(vm.missing.count)",   label: "Missing",     color: .statusMissing, icon: "questionmark.circle.fill")
            }
            .padding(.horizontal)
        }
    }

    // MARK: - RFID Card

    private var rfidStatusCard: some View {
        WhearCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(rfid.isConnected ? Color.statusCloset.opacity(0.12) : Color.whearSurface)
                        .frame(width: 48, height: 48)
                    Image(systemName: rfid.isScanning ? "antenna.radiowaves.left.and.right" : "wifi")
                        .font(.system(size: 20))
                        .foregroundColor(rfid.isConnected ? .statusCloset : .whearSubtext)
                        .symbolEffect(.pulse, isActive: rfid.isScanning)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(rfid.isConnected ? "RFID Reader Connected" : "RFID Reader Offline")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.whearText)
                    if let last = rfid.lastScan {
                        Text("Last scan \(last.formatted(.relative(presentation: .named)))")
                            .font(.whearCaption)
                            .foregroundColor(.whearSubtext)
                    } else {
                        Text(rfid.isConnected ? "Scanning…" : "Configure in Settings")
                            .font(.whearCaption)
                            .foregroundColor(.whearSubtext)
                    }
                }
                Spacer()
                if rfid.isConnected {
                    Button {
                        Task { await vm.refreshFromRFID() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                            .foregroundColor(.whearPrimary)
                    }
                }
            }
            .padding(16)
        }
        .padding(.horizontal)
    }

    // MARK: - Recent Activity

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Recent Activity")
            VStack(spacing: 0) {
                ForEach(vm.items.prefix(4)) { item in
                    ActivityRow(item: item)
                        .id("\(item.id)-\(item.status.rawValue)")  // ← force re-render on status change
                    if item.id != vm.items.prefix(4).last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(Color.whearBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            .padding(.horizontal)
        }
    }

    // MARK: - Missing Items

    private var missingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Missing Items")

            VStack(spacing: 0) {
                ForEach(vm.missing) { item in
                    HStack(spacing: 12) {
                        ItemImage(item: item, size: 36, cornerRadius: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.whearText)
                            if let tag = item.tagId {
                                Text("Tag #\(tag)")
                                    .font(.whearMono)
                                    .foregroundColor(.whearSubtext)
                            }
                        }
                        Spacer()
                        StatusBadge(status: .missing)
                    }
                    .padding(14)
                    if item.id != vm.missing.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(Color.whearBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.statusMissing.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
            .padding(.horizontal)
        }
    }

    // MARK: - Most Worn

    private var mostWorn: some View {
        let topItems = vm.items.sorted { $0.wearCount > $1.wearCount }.prefix(5)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Most Worn")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(topItems)) { item in
                        WornItemCard(item: item)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Sub-components

private struct StatCard: View {
    let value: String
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.whearCaption)
                .foregroundColor(.whearSubtext)
        }
        .padding(16)
        .frame(width: 130)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ActivityRow: View {
    let item: ClothingItem

    var body: some View {
        HStack(spacing: 12) {
            ItemImage(item: item, size: 36, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.whearText)
                Text(item.category.rawValue)
                    .font(.whearCaption)
                    .foregroundColor(.whearSubtext)
            }
            Spacer()
            StatusBadge(status: item.status, compact: true)
        }
        .padding(14)
    }
}

private struct WornItemCard: View {
    let item: ClothingItem

    var body: some View {
        VStack(spacing: 8) {
            ItemImage(item: item, size: 64, cornerRadius: 12)
            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.whearText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("\(item.wearCount)×")
                .font(.whearCaption)
                .foregroundColor(.whearSubtext)
        }
        .frame(width: 80)
    }
}
