import Foundation
import CoreBluetooth
import IOBluetooth

struct HeadphoneBatteryInfo: Identifiable, Equatable {
    let id: String                 // stable key: BT addressString OR peripheral UUID string
    var name: String
    var batteryPercent: Int?
    var lastUpdated: Date?
    var isConnected: Bool
}

@MainActor
final class HeadphonesBatteryViewModel: NSObject, ObservableObject {

    @Published private(set) var connectedHeadphones: [HeadphoneBatteryInfo] = []
    @Published private(set) var errorText: String?

    // BLE Battery Service + Battery Level Characteristic
    private let batteryService = CBUUID(string: "180F")
    private let batteryLevelChar = CBUUID(string: "2A19")

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var batteryChars: [UUID: CBCharacteristic] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func start() {
        // state callback triggers refresh
    }

    func stop() {
        peripherals.values.forEach { p in
            central.cancelPeripheralConnection(p)
        }
        peripherals.removeAll()
        batteryChars.removeAll()
        connectedHeadphones.removeAll()
    }

    func refresh() {
        errorText = nil

        // 1) Primary path (works for AirPods/Beats in many cases)
        refreshIOBluetoothAudioDevices()

        // 2) Fallback BLE path (for devices that expose Battery Service)
        guard central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [batteryService])
        handleConnectedBLEPeripherals(connected)
    }

    // MARK: - Audio filtering

    private func isLikelyHeadphonesName(_ name: String) -> Bool {
        let n = name.lowercased()

        // hard excludes
        if n.contains("keyboard") || n.contains("mouse") || n.contains("trackpad") { return false }
        if n.contains("magic keyboard") || n.contains("magic mouse") || n.contains("logitech") { return false }

        // includes
        if n.contains("airpods") || n.contains("beats") { return true }
        if n.contains("headphone") || n.contains("headphones") { return true }
        if n.contains("headset") { return true }
        if n.contains("earbuds") { return true }

        // якщо не впізнали — не показуємо, щоб не тягнути периферію типу миші/клави
        return false
    }

    // MARK: - IOBluetooth (AirPods-friendly)

    private func refreshIOBluetoothAudioDevices() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }

        let audio = paired
            .filter { $0.isConnected() }
            .filter { device in
                let name = (device.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return isLikelyHeadphonesName(name)
            }

        // Map IOBluetooth devices -> HeadphoneBatteryInfo
        let items: [HeadphoneBatteryInfo] = audio.map { d in
            let name = (d.name ?? "Audio device").trimmingCharacters(in: .whitespacesAndNewlines)
            let id = d.addressString ?? "iobt-\(name)" // addressString is the best stable key

            return HeadphoneBatteryInfo(
                id: id,
                name: name,
                batteryPercent: d.bd_batteryPercent,   // best-effort (see extension below)
                lastUpdated: Date(),
                isConnected: true
            )
        }

        // Replace current list with IOBluetooth results first.
        // BLE refresh will "merge in" any additional info later.
        connectedHeadphones = items
    }

    // MARK: - BLE fallback (180F/2A19)

    private func handleConnectedBLEPeripherals(_ list: [CBPeripheral]) {
        for p in list {
            let name = (p.name ?? "Bluetooth device").trimmingCharacters(in: .whitespacesAndNewlines)
            guard isLikelyHeadphonesName(name) else { continue } // filter out mouse/keyboard etc.

            if peripherals[p.identifier] == nil {
                peripherals[p.identifier] = p
                p.delegate = self
                p.discoverServices([batteryService])
            }

            // merge into list
            let id = "ble-\(p.identifier.uuidString)"
            upsert(id: id, name: name, isConnected: true)
        }

        // remove BLE items that disconnected (keep iobt items intact)
        let bleIDs = Set(list.map { "ble-\($0.identifier.uuidString)" })
        connectedHeadphones = connectedHeadphones.filter { item in
            // keep iobt entries always (they’ll be refreshed each refresh call anyway)
            if item.id.hasPrefix("iobt-") { return true }
            if item.id.hasPrefix("ble-") { return bleIDs.contains(item.id) }
            return true
        }
    }

    private func upsert(id: String, name: String, isConnected: Bool) {
        if let idx = connectedHeadphones.firstIndex(where: { $0.id == id }) {
            connectedHeadphones[idx].name = name
            connectedHeadphones[idx].isConnected = isConnected
        } else {
            connectedHeadphones.append(.init(id: id, name: name, batteryPercent: nil, lastUpdated: nil, isConnected: isConnected))
        }
    }

    private func setBattery(id: String, percent: Int) {
        guard let idx = connectedHeadphones.firstIndex(where: { $0.id == id }) else { return }
        connectedHeadphones[idx].batteryPercent = percent
        connectedHeadphones[idx].lastUpdated = Date()
    }
}

// MARK: - CBCentralManagerDelegate

extension HeadphonesBatteryViewModel: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            refresh()
        case .unsupported:
            errorText = "Bluetooth unsupported on this Mac."
        case .unauthorized:
            errorText = "Bluetooth permission denied."
        default:
            break
        }
    }
}

// MARK: - CBPeripheralDelegate

extension HeadphonesBatteryViewModel: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            errorText = error.localizedDescription
            return
        }
        guard let services = peripheral.services else { return }
        for s in services where s.uuid == batteryService {
            peripheral.discoverCharacteristics([batteryLevelChar], for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            errorText = error.localizedDescription
            return
        }
        guard let chars = service.characteristics else { return }
        for ch in chars where ch.uuid == batteryLevelChar {
            batteryChars[peripheral.identifier] = ch
            peripheral.readValue(for: ch)
            peripheral.setNotifyValue(true, for: ch)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            errorText = error.localizedDescription
            return
        }
        guard characteristic.uuid == batteryLevelChar,
              let data = characteristic.value,
              let value = data.first
        else { return }

        let id = "ble-\(peripheral.identifier.uuidString)"
        setBattery(id: id, percent: Int(value))
    }
}

// MARK: - IOBluetooth best-effort battery extraction

private extension IOBluetoothDevice {
    var bd_batteryPercent: Int? {
        guard self.responds(to: Selector(("batteryPercent"))) else { return nil }

        return ObjC.catchException {
            (self.value(forKey: "batteryPercent") as? NSNumber)?.intValue
        }
    }
}
