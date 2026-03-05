#if os(macOS)
import SwiftUI
import PocketMeshServices

/// macOS device scanner sheet that replaces the iOS AccessorySetupKit picker.
///
/// Shows BLE devices advertising the Nordic UART service with name and signal strength.
/// Selecting a device initiates a direct BLE connection via ``ConnectionManager/connectToScannedDevice(deviceID:)``.
struct BLEScannerSheet: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var isConnecting = false
    @State private var connectingDeviceID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Device")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    appState.connectionManager.bleScanner.stopScanning()
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Content
            if appState.connectionManager.bleScanner.bluetoothState != .poweredOn
                && !appState.connectionManager.bleScanner.isScanning
            {
                bluetoothUnavailableView
            } else if appState.connectionManager.bleScanner.discoveredPeripherals.isEmpty {
                scanningPlaceholder
            } else {
                deviceList
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            appState.connectionManager.bleScanner.startScanning()
        }
        .onDisappear {
            appState.connectionManager.bleScanner.stopScanning()
        }
        .alert("Connection Failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var bluetoothUnavailableView: some View {
        ContentUnavailableView {
            Label("Bluetooth Unavailable", systemImage: "bluetooth.slash")
        } description: {
            Text("Please enable Bluetooth in System Settings to scan for devices.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning for MeshCore devices...")
                .foregroundStyle(.secondary)
            Text("Make sure your device is powered on and nearby.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deviceList: some View {
        List(sortedPeripherals) { peripheral in
            Button {
                connectToDevice(peripheral)
            } label: {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.tint)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(peripheral.name)
                            .font(.body)
                        Text(peripheral.id.uuidString.prefix(8).uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    signalIndicator(rssi: peripheral.rssi)

                    if connectingDeviceID == peripheral.id {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 8)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)
        }
    }

    /// Peripherals sorted by signal strength (strongest first)
    private var sortedPeripherals: [DiscoveredPeripheral] {
        appState.connectionManager.bleScanner.discoveredPeripherals
            .sorted { $0.rssi > $1.rssi }
    }

    // MARK: - Signal Indicator

    private func signalIndicator(rssi: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: bar, rssi: rssi))
                    .frame(width: 3, height: CGFloat(4 + bar * 3))
            }
        }
        .frame(width: 20, height: 16)
    }

    private func barColor(for bar: Int, rssi: Int) -> Color {
        let activeBars: Int
        switch rssi {
        case -50...0: activeBars = 4
        case -65 ..< -50: activeBars = 3
        case -80 ..< -65: activeBars = 2
        default: activeBars = 1
        }
        return bar < activeBars ? .green : .gray.opacity(0.3)
    }

    // MARK: - Connection

    private func connectToDevice(_ peripheral: DiscoveredPeripheral) {
        guard !isConnecting else { return }

        isConnecting = true
        connectingDeviceID = peripheral.id
        appState.connectionManager.bleScanner.stopScanning()

        Task { @MainActor in
            defer {
                isConnecting = false
                connectingDeviceID = nil
            }

            do {
                try await appState.connectionManager.connectToScannedDevice(deviceID: peripheral.id)
                await appState.wireServicesIfConnected()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                // Restart scanning after failure
                appState.connectionManager.bleScanner.startScanning()
            }
        }
    }
}
#endif
