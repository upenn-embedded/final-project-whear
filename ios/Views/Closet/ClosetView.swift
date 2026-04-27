import SwiftUI

struct ClosetView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var searchText: String = ""
    @State private var selectedFilter: ClothingStatus? = nil
    @State private var selectedCategory: ClothingCategory? = nil
    @State private var isGridView: Bool = false
    @State private var showAddItem: Bool = false
    @State private var selectedItem: ClothingItem? = nil
    @State private var showAlerts: Bool = false

    private var filteredItems: [ClothingItem] {
        vm.items.filter { item in
            let matchSearch  = searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText) || (item.brand ?? "").localizedCaseInsensitiveContains(searchText)
            let matchStatus  = selectedFilter == nil || item.status == selectedFilter
            let matchCat     = selectedCategory == nil || item.category == selectedCategory
            return matchSearch && matchStatus && matchCat
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    navBar
                    searchBar
                    statusFilterRow
                    categoryFilterRow

                    if filteredItems.isEmpty {
                        Spacer()
                        EmptyStateView(
                            icon: "tshirt",
                            title: "No items found",
                            subtitle: "Try adjusting your filters or add a new item",
                            action: "Add Item",
                            onAction: { showAddItem = true }
                        )
                        Spacer()
                    } else if isGridView {
                        gridView
                    } else {
                        listView
                    }
                }
                .background(Color.whearBackground)

                addButton
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showAddItem) {
                AddItemView()
                    .environmentObject(vm)
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailView(item: item)
                    .environmentObject(vm)
            }
            .sheet(isPresented: $showAlerts) {
                AlertsView()
                    .environmentObject(vm)
            }
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Text("My Closet")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundColor(.whearText)

            Spacer()

            HStack(spacing: 14) {
                RFIDStatusBadge()

                Button {
                    showAlerts = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 20))
                            .foregroundColor(.whearText)
                        if vm.alertCount > 0 {
                            Circle()
                                .fill(Color.statusMissing)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Text("\(vm.alertCount)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                )
                                .offset(x: 6, y: -6)
                        }
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.3)) { isGridView.toggle() }
                } label: {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 18))
                        .foregroundColor(.whearText)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.whearSubtext)
            TextField("Search items or brands…", text: $searchText)
                .font(.whearBody)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.whearSubtext)
                }
            }
        }
        .padding(12)
        .background(Color.whearSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    // MARK: - Status filter

    private var statusFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selectedFilter == nil) {
                    withAnimation { selectedFilter = nil }
                }
                ForEach(ClothingStatus.allCases) { status in
                    FilterChip(
                        label: status.rawValue,
                        isSelected: selectedFilter == status,
                        color: status.color
                    ) {
                        withAnimation { selectedFilter = selectedFilter == status ? nil : status }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Category filter

    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All Types", isSelected: selectedCategory == nil) {
                    withAnimation { selectedCategory = nil }
                }
                ForEach(ClothingCategory.allCases) { cat in
                    FilterChip(label: cat.rawValue, isSelected: selectedCategory == cat) {
                        withAnimation { selectedCategory = selectedCategory == cat ? nil : cat }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 10)
    }

    // MARK: - List view

    private var listView: some View {
        List {
            ForEach(filteredItems) { item in
                ItemRowView(item: item)
                    .id("\(item.id)-\(item.status.rawValue)")  // ← add this
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.whearBackground)
                    .onTapGesture { selectedItem = item }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await vm.deleteItem(item) }
                        } label: { Label("Delete", systemImage: "trash") }
                        Button {
                            Task { await vm.updateStatus(item, status: .laundry) }
                        } label: { Label("Laundry", systemImage: "washer") }
                            .tint(.statusLaundry)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await vm.updateStatus(item, status: .closet) }
                        } label: { Label("In Closet", systemImage: "checkmark") }
                            .tint(.statusCloset)
                    }
            }
            Color.clear.frame(height: 80).listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .refreshable { await vm.refreshFromRFID() }
    }

    private var gridView: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filteredItems) { item in
                    GridItemView(item: item)
                        .id("\(item.id)-\(item.status.rawValue)")  // ← add this
                        .onTapGesture { selectedItem = item }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 90)
        }
        .refreshable { await vm.refreshFromRFID() }
    }

    // MARK: - FAB

    private var addButton: some View {
        Button {
            showAddItem = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 58, height: 58)
                .background(Color.whearPrimary)
                .clipShape(Circle())
                .shadow(color: Color.whearPrimary.opacity(0.45), radius: 12, x: 0, y: 6)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 100)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    var color: Color = .whearPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .whearText)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? color : Color.whearSurface)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Item Row

struct ItemRowView: View {
    let item: ClothingItem

    var body: some View {
        HStack(spacing: 14) {
            // Photo if available, otherwise color swatch
            ItemImage(item: item, size: 48, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.whearText)
                HStack(spacing: 6) {
                    Text(item.category.rawValue)
                        .font(.whearCaption)
                        .foregroundColor(.whearSubtext)
                    if let tag = item.tagId {
                        Text("·")
                            .foregroundColor(.whearBorder)
                        Text("#\(tag)")
                            .font(.whearMono)
                            .foregroundColor(.whearSubtext)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: item.status)
                if item.wearCount > 0 {
                    Text("\(item.wearCount)×")
                        .font(.whearCaption)
                        .foregroundColor(.whearSubtext)
                }
            }
        }
        .padding(12)
        .background(Color.whearBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 1)
    }
}

// MARK: - Grid Item

struct GridItemView: View {
    let item: ClothingItem

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let side = geo.size.width
                if let urlString = item.imageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: side, height: side)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        case .failure:
                            RoundedRectangle(cornerRadius: 10)
                                .fill(item.displayColor)
                                .frame(width: side, height: side)
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(item.displayColor.opacity(0.3))
                                    .frame(width: side, height: side)
                                ProgressView().scaleEffect(0.7)
                            }
                        @unknown default:
                            RoundedRectangle(cornerRadius: 10)
                                .fill(item.displayColor)
                                .frame(width: side, height: side)
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(item.displayColor)
                        .frame(width: side, height: side)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                StatusBadge(status: item.status, compact: true)
                    .padding(6)
            }

            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.whearText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}
