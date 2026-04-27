import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var rfid = RFIDService.shared
    @State private var deviceURLInput: String = RFIDService.shared.deviceBaseURL
    @State private var showSaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(rfid.isConnected ? .statusCloset : .whearSubtext)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rfid.isConnected ? "Connected" : "Disconnected")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(rfid.isConnected ? .statusCloset : .whearSubtext)
                            if let last = rfid.lastScan {
                                Text("Last scan: \(last.formatted(.dateTime.hour().minute()))")
                                    .font(.whearCaption)
                                    .foregroundColor(.whearSubtext)
                            }
                        }
                        Spacer()
                        Circle()
                            .fill(rfid.isConnected ? Color.statusCloset : Color.gray.opacity(0.4))
                            .frame(width: 10, height: 10)
                    }
                } header: { Text("RFID Reader Status") }

                Section {
                    TextField("http://192.168.1.x or http://whear.local", text: $deviceURLInput)
                        .font(.system(size: 14, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button {
                        rfid.setDeviceURL(deviceURLInput)
                        rfid.startPolling()
                        showSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSaved = false }
                    } label: {
                        HStack {
                            Text(showSaved ? "Saved!" : "Save & Connect")
                            Spacer()
                            if showSaved { Image(systemName: "checkmark").foregroundColor(.statusCloset) }
                        }
                        .foregroundColor(.whearPrimary)
                    }

                    Button("Test Connection") {
                        Task { await rfid.fetchInventory() }
                    }
                    .foregroundColor(.whearPrimary)
                } header: { Text("Device Configuration") }
                  footer: { Text("Enter the local IP or mDNS hostname of your ESP32 Wi-Fi bridge. The app will poll /inventory every 10 seconds.") }

                Section {
                    LabeledContent("Scan Interval", value: "10 seconds")
                    LabeledContent("Absent After", value: "3 missed scans (~30s)")
                    LabeledContent("Poll Endpoint", value: "/inventory")
                } header: { Text("RFID Settings") }

                Section {
                    Link("View Project Proposal", destination: URL(string: "https://ese.upenn.edu")!)
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build", value: "ESE 3500 · Spring 2026")
                } header: { Text("About Whear") }
            }
            .navigationTitle("Settings")
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
