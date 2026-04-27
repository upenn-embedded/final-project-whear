import SwiftUI
import PhotosUI

struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: AppViewModel

    let item: ClothingItem
    var onSave: ((ClothingItem) -> Void)? = nil

    @State private var name: String
    @State private var brand: String
    @State private var selectedCategory: ClothingCategory
    @State private var selectedColorHex: String
    @State private var notes: String
    @State private var tagId: String

    @State private var capturedImage: UIImage?     = nil
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var showCamera: Bool            = false
    @State private var isSaving: Bool              = false
    @State private var showValidation: Bool        = false

    private let colorOptions: [String] = [
        "#F5F0E8", "#2C2C2C", "#C19A6B", "#3D5A3E", "#4A6FA5",
        "#6E2B3A", "#C4622D", "#888888", "#FFFFFF", "#1A1A1A",
        "#D4C5B0", "#5B7FA6", "#E09B3D", "#9B59B6", "#E74C3C"
    ]

    init(item: ClothingItem, onSave: ((ClothingItem) -> Void)? = nil) {
        self.item   = item
        self.onSave = onSave
        _name               = State(initialValue: item.name)
        _brand              = State(initialValue: item.brand ?? "")
        _selectedCategory   = State(initialValue: item.category)
        _selectedColorHex   = State(initialValue: item.colorHex)
        _notes              = State(initialValue: item.notes ?? "")
        _tagId              = State(initialValue: item.tagId ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack { Color.whearBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        photoSection
                        detailsSection
                        categorySection
                        colorSection
                        tagSection
                        notesSection
                        WhearButton(title: "Save Changes", icon: "checkmark.circle", isLoading: isSaving) { save() }
                            .padding(.horizontal)
                            .padding(.bottom, 32)
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.whearPrimary)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraView(capturedImage: $capturedImage)
            }
        }
    }

    // MARK: - Photo

    private var photoSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.whearSurface)
                    .frame(height: 190)

                if let img = capturedImage {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if let urlString = item.imageUrl, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                            .frame(height: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } placeholder: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(Color(hex: item.colorHex)?.opacity(0.3) ?? Color.whearSurface).frame(height: 190)
                            ProgressView()
                        }
                    } failure: {
                        existingColorPlaceholder
                    }
                } else {
                    existingColorPlaceholder
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if capturedImage != nil {
                    Button { withAnimation { capturedImage = nil } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22)).foregroundColor(.white).shadow(radius: 4)
                    }.padding(12)
                }
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                PhotoSourceButton(icon: "camera.fill", label: "Camera") { showCamera = true }
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    PhotoSourceButtonLabel(icon: "photo.fill", label: "Gallery")
                }
                .onChange(of: selectedPhoto) { _, new in
                    Task {
                        if let data = try? await new?.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) { capturedImage = img }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var existingColorPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: item.colorHex)?.opacity(0.25) ?? Color.whearSurface)
                .frame(height: 190)
            VStack(spacing: 8) {
                Image(systemName: "camera.fill").font(.system(size: 28)).foregroundColor(.whearSubtext)
                Text("Tap to replace photo").font(.system(size: 13)).foregroundColor(.whearSubtext)
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Name & Brand")
                .font(.system(size: 16, weight: .semibold)).foregroundColor(.whearText)
                .padding(.horizontal)
            VStack(spacing: 0) {
                EditFormField(label: "Name", placeholder: "e.g. Camel Wool Coat",
                              text: $name, isRequired: true, showValidation: showValidation)
                Divider().padding(.leading, 16)
                EditFormField(label: "Brand", placeholder: "e.g. Arket",
                              text: $brand, isRequired: false, showValidation: false)
            }
            .background(Color.whearBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            .padding(.horizontal)
        }
    }

    // MARK: - Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Category")
                .font(.system(size: 16, weight: .semibold)).foregroundColor(.whearText)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ClothingCategory.allCases) { cat in
                        Button {
                            withAnimation(.spring(response: 0.2)) { selectedCategory = cat }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon).font(.system(size: 12))
                                Text(cat.rawValue).font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(selectedCategory == cat ? .white : .whearText)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(selectedCategory == cat ? Color.whearPrimary : Color.whearSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Color

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Color").font(.system(size: 16, weight: .semibold)).foregroundColor(.whearText)
                Spacer()
                ColorSwatch(color: Color(hex: selectedColorHex) ?? .gray, size: 28, cornerRadius: 7)
            }.padding(.horizontal)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                ForEach(colorOptions, id: \.self) { hex in
                    Button {
                        withAnimation(.spring(response: 0.2)) { selectedColorHex = hex }
                    } label: {
                        ZStack {
                            Circle().fill(Color(hex: hex) ?? .gray).frame(width: 34, height: 34)
                                .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 0.5))
                            if selectedColorHex == hex {
                                Circle().stroke(Color.whearPrimary, lineWidth: 2.5).frame(width: 38, height: 38)
                            }
                        }
                    }
                }
            }.padding(.horizontal)
        }
    }

    // MARK: - RFID Tag

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RFID Tag").font(.system(size: 16, weight: .semibold))
                .foregroundColor(.whearText).padding(.horizontal)
            HStack(spacing: 8) {
                Image(systemName: "tag.fill").foregroundColor(.whearSubtext)
                TextField("Tag ID (e.g. A1F3)", text: $tagId)
                    .font(.whearMono).textInputAutocapitalization(.characters)
                if !tagId.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.statusCloset).font(.system(size: 14))
                }
            }
            .padding(14)
            .background(Color.whearSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes").font(.system(size: 16, weight: .semibold))
                .foregroundColor(.whearText).padding(.horizontal)
            TextEditor(text: $notes)
                .font(.whearBody).foregroundColor(.whearText)
                .frame(height: 80).padding(12)
                .background(Color.whearSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Care instructions, size, etc.")
                            .font(.whearBody).foregroundColor(.whearSubtext)
                            .padding(.horizontal, 28).padding(.top, 20)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Save

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            showValidation = true; return
        }
        isSaving = true
        var updated        = item
        updated.name       = name
        updated.brand      = brand.isEmpty ? nil : brand
        updated.category   = selectedCategory
        updated.colorHex   = selectedColorHex
        updated.notes      = notes.isEmpty ? nil : notes
        updated.tagId      = tagId.isEmpty ? nil : tagId

        Task {
            await vm.addItem(updated, image: capturedImage)
            isSaving = false
            onSave?(updated)
            dismiss()
        }
    }
}

// MARK: - Form field helper

private struct EditFormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let isRequired: Bool
    let showValidation: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .medium)).foregroundColor(.whearSubtext)
                .frame(width: 60, alignment: .leading)
            TextField(placeholder, text: $text).font(.whearBody)
            if isRequired && showValidation && text.isEmpty {
                Image(systemName: "exclamationmark.circle.fill").foregroundColor(.statusMissing)
            }
        }.padding(14)
    }
}
