import SwiftUI

struct AlertsView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.missing.isEmpty && vm.inLaundry.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.statusCloset)
                        Text("All Clear!")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.whearText)
                        Text("No missing or outstanding laundry items.")
                            .font(.whearBody)
                            .foregroundColor(.whearSubtext)
                        Spacer()
                    }
                } else {
                    List {
                        if !vm.missing.isEmpty {
                            Section {
                                ForEach(vm.missing) { item in
                                    AlertRow(item: item, onResolve: {
                                        Task { await vm.updateStatus(item, status: .closet) }
                                    })
                                }
                            } header: {
                                Label("Missing Items", systemImage: "questionmark.circle.fill")
                                    .foregroundColor(.statusMissing)
                            }
                        }

                        if !vm.inLaundry.isEmpty {
                            Section {
                                ForEach(vm.inLaundry) { item in
                                    AlertRow(item: item, onResolve: {
                                        Task { await vm.updateStatus(item, status: .closet) }
                                    })
                                }
                            } header: {
                                Label("In Laundry", systemImage: "washer.fill")
                                    .foregroundColor(.statusLaundry)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color.whearBackground)
            .navigationTitle("Alerts")
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

private struct AlertRow: View {
    let item: ClothingItem
    let onResolve: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ColorSwatch(color: item.displayColor, size: 38, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.whearText)
                Text(item.category.rawValue)
                    .font(.whearCaption)
                    .foregroundColor(.whearSubtext)
            }
            Spacer()
            Button("Resolved", action: onResolve)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.statusCloset)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.statusCloset.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}
