import SwiftUI
import PhotosUI

struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: AppViewModel

    @State private var step: Int
    @State private var tagId: String
    @State private var isScanning: Bool     = false
    @State private var scanned: Bool

    @State private var name: String                         = ""
    @State private var brand: String                        = ""
    @State private var selectedCategory: ClothingCategory  = .tops
    @State private var selectedColorHex: String             = "#888888"
    @State private var notes: String                        = ""

    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var capturedImage: UIImage?           = nil
    @State private var showCamera: Bool                  = false

    @State private var isSaving: Bool       = false
    @State private var showValidation: Bool = false

    private let prefilledTagId: String?

    init(prefilledTagId: String? = nil) {
        self.prefilledTagId = prefilledTagId
        _step    = State(initialValue: prefilledTagId != nil ? 2 : 1)
        _tagId   = State(initialValue: prefilledTagId ?? "")
        _scanned = State(initialValue: prefilledTagId != nil)
    }

    private let colorOptions: [String] = [
        "#F5F0E8", "#2C2C2C", "#C19A6B", "#3D5A3E", "#4A6FA5",
        "#6E2B3A", "#C4622D", "#888888", "#FFFFFF", "#1A1A1A",
        "#D4C5B0", "#5B7FA6", "#E09B3D", "#9B59B6", "#E74C3C"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.whearBackground.ignoresSafeArea()
                if step == 1 {
                    tagScanStep
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                } else {
                    detailsStep
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.28), value: step)
            .navigationBarHidden(true)
            .sheet(isPresented: $showCamera) { CameraView(capturedImage: $capturedImage) }
        }
    }

    // MARK: - Step 1: Tag Scan

    private var tagScanStep: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.whearText).frame(width: 32, height: 32)
                        .background(Color.whearSurface).clipShape(Circle())
                }
                Spacer()
                stepIndicator
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal).padding(.top, 16).padding(.bottom, 8)

            Spacer()

            VStack(spacing: 10) {
                Text("Connect RFID Tag")
                    .font(.system(size: 26, weight: .bold, design: .serif)).foregroundColor(.whearText)
                Text("Scan the tag attached to your garment,\nor enter the ID manually below")
                    .font(.whearBody).foregroundColor(.whearSubtext)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }

            Spacer(minLength: 32)

            ZStack {
                Circle().fill(Color.whearPrimary.opacity(0.08)).frame(width: 180, height: 180)
                    .scaleEffect(isScanning ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isScanning)
                Circle().fill(Color.whearPrimary.opacity(0.15)).frame(width: 130, height: 130)
                    .scaleEffect(isScanning ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.2), value: isScanning)
                Circle().fill(scanned ? Color.statusCloset : Color.whearPrimary).frame(width: 82, height: 82)
                    .overlay(Image(systemName: scanned ? "checkmark" : "wave.3.right")
                        .font(.system(size: 28, weight: .medium)).foregroundColor(.white))
            }
            .padding(.bottom, 16)

            Text(scanned ? "Tag #\(tagId) detected!" : isScanning ? "Scanning…" : "Ready to scan")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(scanned ? .statusCloset : .whearSubtext)
                .animation(.easeInOut, value: scanned)

            Spacer(minLength: 32)

            VStack(alignment: .leading, spacing: 8) {
                Text("Tag ID").font(.system(size: 13, weight: .medium))
                    .foregroundColor(.whearSubtext).padding(.horizontal)

                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "tag.fill").foregroundColor(.whearSubtext)
                        TextField("e.g. A1F3", text: $tagId)
                            .font(.whearMono).textInputAutocapitalization(.characters)
                            .onChange(of: tagId) { _, _ in if !tagId.isEmpty { scanned = false } }
                    }
                    .padding(12).background(Color.whearSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button { simulateScan() } label: {
                        Image(systemName: "wave.3.right").font(.system(size: 16))
                            .foregroundColor(.white).frame(width: 46, height: 46)
                            .background(isScanning ? Color.whearSubtext : Color.whearPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isScanning)
                }
                .padding(.horizontal)
            }

            Spacer(minLength: 32)

            VStack(spacing: 12) {
                WhearButton(
                    title: isScanning ? "Scanning…" : (scanned ? "Tag Added — Next" : "Next"),
                    icon: "arrow.right", isLoading: isScanning
                ) { withAnimation { step = 2 } }
                .padding(.horizontal).disabled(isScanning)

                Button("Skip — No Tag") { tagId = ""; withAnimation { step = 2 } }
                    .font(.system(size: 15)).foregroundColor(.whearSubtext)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Step 2: Item Details

    private var detailsStep: some View {
        VStack(spacing: 0) {
            HStack {
                if prefilledTagId == nil {
                    Button { withAnimation { step = 1 } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.whearText).frame(width: 32, height: 32)
                            .background(Color.whearSurface).clipShape(Circle())
                    }
                } else {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.whearText).frame(width: 32, height: 32)
                            .background(Color.whearSurface).clipShape(Circle())
                    }
                }
                Spacer()
                stepIndicator
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal).padding(.top, 16).padding(.bottom, 4)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text("Item Details")
                            .font(.system(size: 26, weight: .bold, design: .serif)).foregroundColor(.whearText)

                        if !tagId.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                                    .foregroundColor(.statusCloset)
                                Text("Tag #\(tagId) linked").font(.whearCaption).foregroundColor(.statusCloset)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Color.statusCloset.opacity(0.1)).clipShape(Capsule())
                        }

                        if prefilledTagId != nil {
                            Text("A new tag was detected in your closet.\nFill in the item details below.")
                                .font(.whearCaption).foregroundColor(.whearSubtext)
                                .multilineTextAlignment(.center).padding(.horizontal, 32)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.top, 8)

                    photoSection
                    detailsSection
                    categorySection
                    colorSection
                    notesSection

                    WhearButton(title: "Add to Closet", icon: "plus.circle", isLoading: isSaving) { save() }
                        .padding(.horizontal).padding(.bottom, 32)
                }
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(1...2, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Color.whearPrimary : Color.whearBorder)
                    .frame(width: i == step ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: step)
            }
        }
    }

    // MARK: - Photo section

    private var photoSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color.whearSurface).frame(height: 190)
                if let img = capturedImage {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.fill").font(.system(size: 34)).foregroundColor(.whearSubtext)
                        Text("Add a photo").font(.system(size: 14)).foregroundColor(.whearSubtext)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if capturedImage != nil {
                    Button { withAnimation { capturedImage = nil } } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22))
                            .foregroundColor(.white).shadow(radius: 4)
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

    // MARK: - Details section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Name & Brand").font(.system(size: 16, weight: .semibold))
                .foregroundColor(.whearText).padding(.horizontal)
            VStack(spacing: 0) {
                FormField(label: "Name", placeholder: "e.g. Camel Wool Coat",
                          text: $name, isRequired: true, showValidation: showValidation)
                Divider().padding(.leading, 16)
                FormField(label: "Brand", placeholder: "e.g. Arket",
                          text: $brand, isRequired: false, showValidation: false)
            }
            .background(Color.whearBackground).clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2).padding(.horizontal)
        }
    }

    // MARK: - Category section

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Category").font(.system(size: 16, weight: .semibold))
                .foregroundColor(.whearText).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ClothingCategory.allCases) { cat in
                        Button { withAnimation(.spring(response: 0.2)) { selectedCategory = cat } } label: {
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

    // MARK: - Color section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Color").font(.system(size: 16, weight: .semibold)).foregroundColor(.whearText)
                Spacer()
                ColorSwatch(color: Color(hex: selectedColorHex) ?? .gray, size: 28, cornerRadius: 7)
            }.padding(.horizontal)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                ForEach(colorOptions, id: \.self) { hex in
                    Button { withAnimation(.spring(response: 0.2)) { selectedColorHex = hex } } label: {
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

    // MARK: - Notes section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes").font(.system(size: 16, weight: .semibold))
                .foregroundColor(.whearText).padding(.horizontal)
            TextEditor(text: $notes).font(.whearBody).foregroundColor(.whearText)
                .frame(height: 80).padding(12).background(Color.whearSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Care instructions, size, etc.").font(.whearBody).foregroundColor(.whearSubtext)
                            .padding(.horizontal, 28).padding(.top, 20).allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Save

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { showValidation = true; return }
        isSaving = true
        let item = ClothingItem(
            name: name, category: selectedCategory, colorHex: selectedColorHex,
            status: .closet, tagId: tagId.isEmpty ? nil : tagId,
            brand: brand.isEmpty ? nil : brand, notes: notes.isEmpty ? nil : notes
        )
        Task { await vm.addItem(item, image: capturedImage); isSaving = false; dismiss() }
    }

    private func simulateScan() {
        isScanning = true; scanned = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            tagId = String(format: "%04X", Int.random(in: 0x1000...0xFFFF))
            isScanning = false; scanned = true
        }
    }
}

// MARK: - Helpers

private struct FormField: View {
    let label: String; let placeholder: String
    @Binding var text: String
    let isRequired: Bool; let showValidation: Bool
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundColor(.whearSubtext)
                .frame(width: 60, alignment: .leading)
            TextField(placeholder, text: $text).font(.whearBody)
            if isRequired && showValidation && text.isEmpty {
                Image(systemName: "exclamationmark.circle.fill").foregroundColor(.statusMissing)
            }
        }.padding(14)
    }
}

struct PhotoSourceButton: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View { Button(action: action) { PhotoSourceButtonLabel(icon: icon, label: label) } }
}

struct PhotoSourceButtonLabel: View {
    let icon: String; let label: String
    var body: some View {
        HStack(spacing: 8) { Image(systemName: icon); Text(label).font(.system(size: 14, weight: .medium)) }
            .foregroundColor(.whearText).frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(Color.whearSurface).clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

struct CameraView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController(); p.sourceType = .camera
        p.delegate = context.coordinator; p.allowsEditing = true; return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraView; init(_ p: CameraView) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.capturedImage = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}

struct TagScanView: View {
    @Binding var tagId: String
    @Environment(\.dismiss) private var dismiss
    @State private var isScanning = false
    @State private var scanned = false
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Scan RFID Tag").font(.system(size: 24, weight: .bold, design: .serif)).foregroundColor(.whearText)
            Text("Hold your phone near the RFID tag attached to your garment")
                .font(.whearBody).foregroundColor(.whearSubtext).multilineTextAlignment(.center).padding(.horizontal, 40)
            ZStack {
                Circle().fill(Color.whearPrimary.opacity(0.1)).frame(width: 160, height: 160)
                    .scaleEffect(isScanning ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isScanning)
                Circle().fill(Color.whearPrimary.opacity(0.2)).frame(width: 120, height: 120)
                    .scaleEffect(isScanning ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.2), value: isScanning)
                Circle().fill(scanned ? Color.statusCloset : Color.whearPrimary).frame(width: 80, height: 80)
                    .overlay(Image(systemName: scanned ? "checkmark" : "wave.3.right")
                        .font(.system(size: 28, weight: .medium)).foregroundColor(.white))
            }
            Text(scanned ? "Tag #\(tagId) registered!" : isScanning ? "Scanning…" : "Ready to scan")
                .font(.system(size: 16, weight: .medium)).foregroundColor(scanned ? .statusCloset : .whearSubtext)
            Spacer()
            VStack(spacing: 12) {
                if !scanned {
                    WhearButton(title: isScanning ? "Scanning…" : "Start Scan", icon: "wave.3.right") { simulateScan() }
                        .padding(.horizontal, 40).disabled(isScanning)
                } else {
                    WhearButton(title: "Use This Tag") { dismiss() }.padding(.horizontal, 40)
                }
                Button("Enter Manually") { dismiss() }.font(.system(size: 15)).foregroundColor(.whearSubtext)
            }.padding(.bottom, 40)
        }
        .background(Color.whearBackground).onAppear { isScanning = false }
    }
    private func simulateScan() {
        isScanning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            tagId = String(format: "%04X", Int.random(in: 0x1000...0xFFFF))
            isScanning = false; scanned = true
        }
    }
}
