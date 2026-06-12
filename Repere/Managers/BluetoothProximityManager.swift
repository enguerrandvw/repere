import Foundation
import CoreBluetooth
import Combine

/// Uses CoreBluetooth to measure RSSI (signal strength) between peers
/// and convert it to an approximate distance. Works indoors, no special
/// signing required, and is FAR more accurate than GPS at close range.
final class BluetoothProximityManager: NSObject, ObservableObject {

    // MARK: - BLE Service / Characteristic UUIDs
    // Custom UUID for Repère proximity service
    static let serviceUUID = CBUUID(string: "B5E3A4F1-2C7D-4E8A-9F1B-3D6C8E2A7F04")
    static let nameCharUUID = CBUUID(string: "B5E3A4F2-2C7D-4E8A-9F1B-3D6C8E2A7F04")

    // MARK: - Bluetooth objects
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var rssiTimer: Timer?

    // MARK: - Published State
    /// peerName → (distance in meters, last update)
    @Published var peerDistances: [String: Double] = [:]

    // MARK: - Config
    private var displayName: String = ""
    private var groupCode: String = ""

    // MARK: - RSSI → Distance calibration
    /// RSSI at 1 meter (calibrated for iPhone, typically -55 to -65)
    private let measuredPowerAt1m: Double = -59.0
    /// Path-loss exponent (2.0 = free space, 2.7 = typical indoor)
    private let pathLossExponent: Double = 2.5

    // MARK: - RSSI Smoothing
    /// Store last N RSSI readings per peripheral for averaging
    private var rssiHistory: [UUID: [Double]] = [:]
    private let rssiHistorySize = 8

    // MARK: - Public API

    func start(displayName: String, groupCode: String) {
        self.displayName = displayName
        self.groupCode = groupCode

        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func stop() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        centralManager?.stopScan()
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        discoveredPeripherals.removeAll()
        rssiHistory.removeAll()
        peerDistances.removeAll()
    }

    // MARK: - RSSI → Distance Conversion

    /// Convert smoothed RSSI to distance in meters using log-distance path loss model
    private func rssiToDistance(_ rssi: Double) -> Double {
        // Formula: distance = 10 ^ ((measuredPower - rssi) / (10 * n))
        let distance = pow(10.0, (measuredPowerAt1m - rssi) / (10.0 * pathLossExponent))
        return max(0.1, min(distance, 100.0)) // Clamp 0.1m - 100m
    }

    /// Add RSSI reading and return smoothed average
    private func smoothRSSI(for peripheralID: UUID, newRSSI: Double) -> Double {
        var history = rssiHistory[peripheralID] ?? []
        history.append(newRSSI)
        if history.count > rssiHistorySize {
            history.removeFirst()
        }
        rssiHistory[peripheralID] = history

        // Weighted average: recent readings count more
        var weightedSum = 0.0
        var weightTotal = 0.0
        for (i, rssi) in history.enumerated() {
            let weight = Double(i + 1) // newer = higher weight
            weightedSum += rssi * weight
            weightTotal += weight
        }
        return weightedSum / weightTotal
    }

    // MARK: - Periodic RSSI polling

    private func startRSSIPolling() {
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for (_, peripheral) in self.discoveredPeripherals {
                if peripheral.state == .connected {
                    peripheral.readRSSI()
                }
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothProximityManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        // Scan for our custom service
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        print("📶 BLE scanning started")
    }

    func centralManager(_ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber) {
        let rssiValue = RSSI.doubleValue
        guard rssiValue < 0 && rssiValue > -100 else { return } // Filter invalid

        // Extract peer name from advertisement local name
        let peerName: String
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            peerName = localName
        } else {
            peerName = peripheral.identifier.uuidString.prefix(8).description
        }

        // Smooth and convert
        let smoothedRSSI = smoothRSSI(for: peripheral.identifier, newRSSI: rssiValue)
        let distance = rssiToDistance(smoothedRSSI)

        DispatchQueue.main.async {
            self.peerDistances[peerName] = distance
        }

        // Connect for continuous RSSI if not already
        if discoveredPeripherals[peripheral.identifier] == nil {
            discoveredPeripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("📶 BLE connected to peripheral: \(peripheral.identifier)")
        peripheral.discoverServices([Self.serviceUUID])
        startRSSIPolling()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Reconnect automatically
        discoveredPeripherals.removeValue(forKey: peripheral.identifier)
        if centralManager?.state == .poweredOn {
            centralManager?.connect(peripheral, options: nil)
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothProximityManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.nameCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics where char.uuid == Self.nameCharUUID {
            peripheral.readValue(for: char)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.nameCharUUID,
              let data = characteristic.value,
              let name = String(data: data, encoding: .utf8) else { return }

        // We now know this peripheral's display name
        // Update the distance entry with the correct name
        if let oldDistance = peerDistances.values.first {
            DispatchQueue.main.async {
                self.peerDistances[name] = oldDistance
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        let rssiValue = RSSI.doubleValue
        guard rssiValue < 0 && rssiValue > -100 else { return }

        let smoothedRSSI = smoothRSSI(for: peripheral.identifier, newRSSI: rssiValue)
        let distance = rssiToDistance(smoothedRSSI)

        // Find peer name for this peripheral
        let peerName = discoveredPeripherals.first(where: { $0.key == peripheral.identifier })
            .map { _ in peripheral.name ?? peripheral.identifier.uuidString.prefix(8).description }
            ?? "Unknown"

        DispatchQueue.main.async {
            self.peerDistances[peerName] = distance
        }
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BluetoothProximityManager: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }

        // Create our service with the peer name characteristic
        let nameChar = CBMutableCharacteristic(
            type: Self.nameCharUUID,
            properties: [.read],
            value: displayName.data(using: .utf8),
            permissions: [.readable]
        )

        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [nameChar]
        peripheral.add(service)

        // Start advertising
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: displayName
        ])
        print("📶 BLE advertising started as: \(displayName)")
    }
}
