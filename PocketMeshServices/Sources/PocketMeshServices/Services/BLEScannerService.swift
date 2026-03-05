#if os(macOS)
@preconcurrency import CoreBluetooth
import Foundation

/// A discovered BLE peripheral from scanning
public struct DiscoveredPeripheral: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let lastSeen: Date
}

/// Scans for MeshCore BLE devices on macOS using CoreBluetooth.
///
/// Replaces AccessorySetupKit (iOS-only) for device discovery on macOS.
/// Uses ``BLEServiceUUID/nordicUART`` to filter for MeshCore devices.
@MainActor @Observable
public final class BLEScannerService {
    private let logger = PersistentLogger(subsystem: "com.pocketmesh.services", category: "BLEScanner")

    /// Currently discovered peripherals, sorted by signal strength
    public private(set) var discoveredPeripherals: [DiscoveredPeripheral] = []

    /// Whether scanning is active
    public private(set) var isScanning = false

    /// Current Bluetooth power state
    public private(set) var bluetoothState: CBManagerState = .unknown

    private var centralManager: CBCentralManager?
    private var scannerDelegate: ScannerDelegate?

    public init() {}

    /// Start scanning for MeshCore devices advertising Nordic UART service
    public func startScanning() {
        guard !isScanning else { return }

        discoveredPeripherals = []
        let delegate = ScannerDelegate(service: self)
        self.scannerDelegate = delegate
        centralManager = CBCentralManager(delegate: delegate, queue: .main)
        // Actual scan starts in centralManagerDidUpdateState when .poweredOn
    }

    /// Stop scanning and release the central manager
    public func stopScanning() {
        if isScanning {
            centralManager?.stopScan()
        }
        centralManager = nil
        scannerDelegate = nil
        isScanning = false
    }

    // MARK: - Delegate Callbacks

    fileprivate func handleStateUpdate(_ state: CBManagerState) {
        bluetoothState = state
        if state == .poweredOn {
            let serviceUUID = CBUUID(string: BLEServiceUUID.nordicUART)
            centralManager?.scanForPeripherals(
                withServices: [serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            isScanning = true
            logger.info("Started scanning for MeshCore devices")
        } else {
            isScanning = false
        }
    }

    fileprivate func handleDiscoveredPeripheral(
        id: UUID,
        name: String,
        rssi: Int
    ) {
        // Ignore peripherals with invalid RSSI (127 means not available)
        guard rssi != 127 else { return }

        if let index = discoveredPeripherals.firstIndex(where: { $0.id == id }) {
            discoveredPeripherals[index] = DiscoveredPeripheral(
                id: id,
                name: name,
                rssi: rssi,
                lastSeen: Date()
            )
        } else {
            discoveredPeripherals.append(DiscoveredPeripheral(
                id: id,
                name: name,
                rssi: rssi,
                lastSeen: Date()
            ))
            logger.info("Discovered device: \(name) (\(id.uuidString.prefix(8)))")
        }
    }
}

// MARK: - CBCentralManagerDelegate

/// Separate delegate class because CBCentralManagerDelegate requires NSObject conformance,
/// and @Observable + @MainActor classes work better without NSObject inheritance.
private final class ScannerDelegate: NSObject, CBCentralManagerDelegate {
    private weak var service: BLEScannerService?

    init(service: BLEScannerService) {
        self.service = service
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        let service = self.service
        Task { @MainActor in
            service?.handleStateUpdate(state)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Extract all values on the callback queue before crossing isolation boundary
        let peripheralID = peripheral.identifier
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown Device"
        let rssiValue = RSSI.intValue
        let service = self.service

        Task { @MainActor in
            service?.handleDiscoveredPeripheral(
                id: peripheralID,
                name: name,
                rssi: rssiValue
            )
        }
    }
}
#endif
