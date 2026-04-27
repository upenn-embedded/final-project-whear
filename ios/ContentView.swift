import SwiftUI

struct ContentView: View {
    @StateObject private var vm  = AppViewModel()
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        Group {
            if hasOnboarded {
                mainTabView
            } else {
                OnboardingView()
            }
        }
        .environmentObject(vm)
        // Single unregistered tag detected (auto on load OR via FAB tap) → AddItemView pre-filled
        .sheet(item: Binding<WrappedString?>(
            get: { vm.pendingRegistrationTagId.map { WrappedString(value: $0) } },
            set: { _ in vm.dismissPendingTag() }
        )) { wrapped in
            AddItemView(prefilledTagId: wrapped.value)
                .environmentObject(vm)
        }
        // FAB tap with no unregistered tags → blank AddItemView
        .sheet(isPresented: $vm.showRegularAddItem) {
            AddItemView()
                .environmentObject(vm)
        }
        // Multiple unregistered tags → generic alert
        .alert(
            "Multiple Unregistered Tags",
            isPresented: $vm.showMultipleUnregisteredAlert
        ) {
            Button("OK", role: .cancel) { vm.showMultipleUnregisteredAlert = false }
        } message: {
            let ids = vm.unregisteredTagIds.joined(separator: ", ")
            Text("\(vm.unregisteredTagIds.count) tags in your scanner are not assigned to any clothing item: \(ids). Open the Closet tab and add items for each tag.")
        }
    }

    private var mainTabView: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $vm.selectedTab) {
                HomeView()
                    .tag(0)
                ClosetView()
                    .tag(1)
                Color.clear.tag(2)  // FAB placeholder
                OutfitsView()
                    .tag(3)
                ShopView()
                    .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.18), value: vm.selectedTab)

            customTabBar
        }
        .ignoresSafeArea(.keyboard)
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            TabBarItem(icon: "house",           label: "Home",    index: 0, selected: $vm.selectedTab)
            TabBarItem(icon: "tshirt",          label: "Closet",  index: 1, selected: $vm.selectedTab,
                       badge: vm.alertCount > 0 ? "\(vm.alertCount)" : nil)
            Spacer()
            TabBarItem(icon: "sparkles",        label: "Outfits", index: 3, selected: $vm.selectedTab,
                       selectedIcon: "sparkles")
            TabBarItem(icon: "bag",             label: "Shop",    index: 4, selected: $vm.selectedTab)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
        .overlay(alignment: .top) {
            // FAB: reconcile first, then route to the right add flow
            Button {
                Task { await vm.handleAddButtonTap() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.whearPrimary)
                    .clipShape(Circle())
                    .shadow(color: Color.whearPrimary.opacity(0.4), radius: 10, x: 0, y: 4)
            }
            .offset(y: -28)
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
    }
}

// MARK: - Helpers

private struct WrappedString: Identifiable {
    let value: String
    var id: String { value }
}

// MARK: - Tab bar item

private struct TabBarItem: View {
    let icon: String
    let label: String
    let index: Int
    @Binding var selected: Int
    var badge: String? = nil
    var selectedIcon: String? = nil

    private var isSelected: Bool { selected == index }
    private var activeIcon: String { isSelected ? (selectedIcon ?? "\(icon).fill") : icon }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25)) { selected = index }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: activeIcon)
                        .font(.system(size: 22))
                        .foregroundColor(isSelected ? .whearPrimary : .whearSubtext)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Color.statusMissing)
                            .clipShape(Circle())
                            .offset(x: 8, y: -6)
                    }
                }
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .whearPrimary : .whearSubtext)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
