import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            WelcomePage(page: $page).tag(0)
            ConnectTagsPage(page: $page).tag(1)
            OnboardDonePage(onFinish: { hasOnboarded = true }).tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.whearBackground)
        .ignoresSafeArea()
    }
}

// MARK: - Welcome page

private struct WelcomePage: View {
    @Binding var page: Int

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                // App icon
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.whearBackground)
                    .frame(width: 110, height: 110)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 8)
                    .overlay(
                        Text("WHEAR")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundColor(.whearText)
                    )

                VStack(spacing: 10) {
                    Text("Your Smart Closet")
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundColor(.whearText)
                        .multilineTextAlignment(.center)
                    Text("Track every garment with RFID. Never lose track of what you own.")
                        .font(.system(size: 16))
                        .foregroundColor(.whearSubtext)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            Spacer()

            VStack(spacing: 20) {
                FeatureBullet(icon: "antenna.radiowaves.left.and.right", title: "Live RFID Scanning", subtitle: "Auto-detects items in your closet")
                FeatureBullet(icon: "sparkles", title: "AI Outfit Suggestions", subtitle: "Personalised to your wardrobe")
                FeatureBullet(icon: "bag.fill", title: "Smart Shopping", subtitle: "Fills gaps in your wardrobe")
            }
            .padding(.horizontal, 32)

            Spacer()

            WhearButton(title: "Get Started") { withAnimation { page = 1 } }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
        }
        .background(Color.whearBackground)
    }
}

// MARK: - Connect Tags page

struct ConnectTagsPage: View {
    @Binding var page: Int
    @State private var registeredTags: [(colorHex: String, name: String, tagId: String)] = [
        ("#C19A6B", "Camel Wool Coat", "A1F3"),
        ("#2C2C2C", "Black Trousers",  "B2D7")
    ]
    @State private var isScanning = false
    @State private var scanPulse  = false
    @ObservedObject private var rfid = RFIDService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Spacer()
                Button("Skip") { page = 2 }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.whearSubtext)
                    .padding()
            }
            .padding(.top, 50)

            Spacer()

            VStack(spacing: 8) {
                Text("Connect Tags")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundColor(.whearText)
                Text("Scan RFID tags to register your items")
                    .font(.whearBody)
                    .foregroundColor(.whearSubtext)
            }

            Spacer(minLength: 30)

            // Scan animation
            ZStack {
                Circle()
                    .fill(Color.whearPrimary.opacity(0.08))
                    .frame(width: 180, height: 180)
                    .scaleEffect(scanPulse ? 1.25 : 1.0)
                    .animation(scanPulse ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default, value: scanPulse)

                Circle()
                    .fill(Color.whearPrimary.opacity(0.15))
                    .frame(width: 130, height: 130)
                    .scaleEffect(scanPulse ? 1.1 : 1.0)
                    .animation(scanPulse ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(0.2) : .default, value: scanPulse)

                Circle()
                    .fill(Color.whearPrimary)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: isScanning ? "antenna.radiowaves.left.and.right" : "wave.3.right")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white)
                            .symbolEffect(.pulse, isActive: isScanning)
                    )
            }

            Text(isScanning ? "Scanning…\nHold tag near phone" : "Tap to start scanning")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isScanning ? .whearPrimary : .whearSubtext)
                .multilineTextAlignment(.center)
                .frame(height: 44)
                .padding(.top, 16)
                .onTapGesture { startScan() }

            Spacer(minLength: 20)

            // Steps
            VStack(alignment: .leading, spacing: 10) {
                StepRow(num: 1, text: "Attach tag to clothing item", done: true)
                StepRow(num: 2, text: "Enable NFC on your phone",    done: true)
                StepRow(num: 3, text: "Scan and register item",      done: false)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 20)

            // Registered list
            if !registeredTags.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("REGISTERED (\(registeredTags.count))")
                        .font(.whearCaption)
                        .foregroundColor(.whearSubtext)
                        .padding(.horizontal, 24)
                    VStack(spacing: 8) {
                        ForEach(registeredTags, id: \.tagId) { tag in
                            HStack(spacing: 12) {
                                ColorSwatch(color: Color(hex: tag.colorHex) ?? .gray, size: 32, cornerRadius: 7)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tag.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.whearText)
                                    Text("Tag #\(tag.tagId)")
                                        .font(.whearMono)
                                        .foregroundColor(.whearSubtext)
                                }
                                Spacer()
                                Text("Tagged")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.statusCloset)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.statusCloset.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(12)
                            .background(Color.whearBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 1)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }

            Spacer()

            WhearButton(title: "Continue") { withAnimation { page = 2 } }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
        }
        .background(Color.whearBackground)
    }

    private func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanPulse  = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            isScanning = false
            scanPulse  = false
        }
    }
}

// MARK: - Done page

private struct OnboardDonePage: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundColor(.statusCloset)
            VStack(spacing: 10) {
                Text("You're all set!")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundColor(.whearText)
                Text("Your smart closet is ready.\nStart adding items and connecting tags.")
                    .font(.whearBody)
                    .foregroundColor(.whearSubtext)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            WhearButton(title: "Open My Closet", icon: "tshirt.fill", action: onFinish)
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
        }
        .background(Color.whearBackground)
    }
}

// MARK: - Small helpers

private struct FeatureBullet: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.whearPrimary)
                .frame(width: 36, height: 36)
                .background(Color.whearPrimary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.whearText)
                Text(subtitle).font(.whearCaption).foregroundColor(.whearSubtext)
            }
            Spacer()
        }
    }
}

private struct StepRow: View {
    let num: Int
    let text: String
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.whearPrimary : Color.whearSurface)
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(num)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.whearSubtext)
                }
            }
            Text(text)
                .font(.system(size: 14, weight: done ? .regular : .medium))
                .strikethrough(done)
                .foregroundColor(done ? .whearSubtext : .whearText)
            Spacer()
        }
    }
}
