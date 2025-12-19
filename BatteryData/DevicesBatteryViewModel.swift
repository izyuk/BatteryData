import Foundation
import CoreBluetooth
import IOBluetooth

struct DeviceBatteryInfo: Identifiable, Equatable {
    let id: String                 // stable key: BT addressString OR peripheral UUID string
    var name: String
    var batteryPercent: Int?
    var lastUpdated: Date?
    var isConnected: Bool
}

@MainActor
final class DevicesBatteryViewModel: NSObject, ObservableObject {
    
    @Published private(set) var connectedDevices: [DeviceBatteryInfo] = []
    @Published private(set) var errorText: String?
    
    // BLE Battery Service + Battery Level Characteristic
    nonisolated static let batteryService = CBUUID(string: "180F")
    nonisolated static let batteryLevelChar = CBUUID(string: "2A19")
    
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var batteryChars: [UUID: CBCharacteristic] = [:]
    
    // MARK: - IOBluetooth connection notifications (fix: app running -> headphones connect later)
    
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:] // key: addressString
    
    private var refreshDebounceTask: Task<Void, Never>?
    
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }
    
    deinit {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }
    
    func start() {
        setupIOBluetoothNotifications()
        refresh()
    }
    
    func stop() {
        // BLE cleanup
        peripherals.values.forEach { p in
            central.cancelPeripheralConnection(p)
        }
        peripherals.removeAll()
        batteryChars.removeAll()
        
        // IOBluetooth notifications cleanup
        teardownIOBluetoothNotifications()
        
        // UI/state cleanup
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        
        connectedDevices.removeAll()
        errorText = nil
    }
    
    func refresh() {
        Task { @MainActor in
            errorText = nil
            
            // 1) Prefer IOBluetooth audio devices (fast + works for “connected audio” view)
            await refreshIOBluetoothAudioDevices()
            
            // 2) Try to enrich nil battery values using system_profiler snapshot (AirPods often here)
            await enrichWithSystemProfilerIfNeeded()
            
            // 3) Fallback BLE battery service
            if central.state == .poweredOn {
                let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
                handleConnectedBLEPeripherals(connected)
            }
        }
    }
    
    // MARK: - IOBluetooth notifications
    
    private func setupIOBluetoothNotifications() {
        guard connectNotification == nil else { return }
        
        // Fires when *any* BT device connects
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(iobtDeviceConnected(_:device:))
        )
        
        // Also register disconnect notifications for devices already connected at app start.
        registerDisconnectForCurrentlyConnectedAudioDevices()
    }
    
    private func teardownIOBluetoothNotifications() {
        connectNotification?.unregister()
        connectNotification = nil
        
        for (_, n) in disconnectNotifications {
            n.unregister()
        }
        disconnectNotifications.removeAll()
    }
    
    private func registerDisconnect(for device: IOBluetoothDevice) {
        guard let addr = device.addressString, disconnectNotifications[addr] == nil else { return }
        
        // Fires when *this specific* device disconnects
        let notif = device.register(
            forDisconnectNotification: self,
            selector: #selector(iobtDeviceDisconnected(_:device:))
        )
        
        if let notif {
            disconnectNotifications[addr] = notif
        }
    }
    
    private func registerDisconnectForCurrentlyConnectedAudioDevices() {
        // We only care about audio-ish devices to avoid registering for everything.
        let audioDevices = getAllIOBluetoothAudioDevices()
        for d in audioDevices where d.isConnected() {
            registerDisconnect(for: d)
        }
    }
    
    private func scheduleRefresh(delay: TimeInterval = 0.35) {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            guard let self else { return }
            let ns = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            await MainActor.run {
                self.refresh()
            }
        }
    }
    
    @objc private func iobtDeviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Register disconnect for this device too.
        registerDisconnect(for: device)
        scheduleRefresh()
    }
    
    @objc private func iobtDeviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if let addr = device.addressString, let n = disconnectNotifications[addr] {
            n.unregister()
            disconnectNotifications.removeValue(forKey: addr)
        }
        scheduleRefresh()
    }
    
    // MARK: - system_profiler enrichment
    
    private func enrichWithSystemProfilerIfNeeded() async {
        guard let json = await SystemProfilerBluetoothReader.fetchBluetoothJSON() else { return }
        
        // 👇 debug helper (safe to keep or remove)
        debugDumpConnectedDevices(from: json)
        
        for idx in connectedDevices.indices {
            let hp = connectedDevices[idx]
            if hp.batteryPercent != nil { continue }
            
            let addr = hp.id
                .replacingOccurrences(of: "-", with: ":")
                .uppercased()
            
            let snap = SystemProfilerBluetoothReader.parseBattery(
                jsonData: json,
                address: addr,
                deviceName: hp.name
            )
            
            print("HP:", hp.name, "id:", hp.id, "addr:", addr, "snap:", snap as Any)
            
            guard let snap else { continue }
            
            let newPercent: Int? = {
                if let l = snap.left, snap.right == nil, snap.casePct == nil {
                    return l
                }
                let vals = [snap.left, snap.right, snap.casePct].compactMap { $0 }
                guard !vals.isEmpty else { return nil }
                return Int(round(Double(vals.reduce(0, +)) / Double(vals.count)))
            }()
            
            guard let newPercent else { continue }
            
            connectedDevices[idx].batteryPercent = newPercent
            connectedDevices[idx].lastUpdated = Date()
        }
    }
    
    private func debugDumpConnectedDevices(from jsonData: Data) {
        guard
            let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let arr = obj["SPBluetoothDataType"] as? [[String: Any]],
            let first = arr.first,
            let connected = first["device_connected"] as? [[String: Any]]
        else {
            print("DEBUG: JSON shape unexpected")
            return
        }
        
        for item in connected {
            guard let (name, propsAny) = item.first,
                  let props = propsAny as? [String: Any]
            else { continue }
            
            let addr = props["device_address"] as? String ?? "-"
            let left = props["device_batteryLevelLeft"] as? String ?? "-"
            let right = props["device_batteryLevelRight"] as? String ?? "-"
            let cs = props["device_batteryLevelCase"] as? String ?? "-"
            
            print("DEBUG DEV:", name, "addr:", addr, "L:", left, "R:", right, "C:", cs)
        }
    }
    
    // MARK: - Audio filtering
    
    private func isLikelyHeadphonesName(_ name: String) -> Bool {
        let n = name.lowercased()
        
        // hard excludes
        if n.contains("keyboard") || n.contains("mouse") || n.contains("trackpad") { return false }
        if n.contains("magic keyboard") || n.contains("magic mouse") || n.contains("logitech") { return false }
        if n.contains("mx keys") || n.contains("mx master") { return false }
        
        // includes
        if n.contains("airpods") { return true }
        if n.contains("beats") { return true }
        if n.contains("headphone") || n.contains("headphones") { return true }
        if n.contains("buds") || n.contains("earbuds") { return true }
        if n.contains("ear") && n.contains("pod") { return true }
        
        // heuristic: audio-like names often short and not “keyboard/mouse”
        return true
    }
    
    private func getAllIOBluetoothAudioDevices() -> [IOBluetoothDevice] {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return paired.filter { device in
            let name = (device.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return isLikelyHeadphonesName(name)
        }
    }
    
    private func refreshIOBluetoothAudioDevices() async {
        let audio = getAllIOBluetoothAudioDevices()
        
        // mark all existing as disconnected; we'll flip to true for those still connected
        for idx in connectedDevices.indices {
            connectedDevices[idx].isConnected = false
        }
        
        for d in audio {
            let name = (d.name ?? "Audio device").trimmingCharacters(in: .whitespacesAndNewlines)
            let id = d.addressString ?? "iobt-\(name)"
            
            guard d.isConnected() else { continue }
            
            // ensure we have disconnect notification for currently connected device
            registerDisconnect(for: d)
            
            if let idx = connectedDevices.firstIndex(where: { $0.id == id }) {
                // UPDATE існуючий — НЕ затираємо batteryPercent
                connectedDevices[idx].name = name
                connectedDevices[idx].isConnected = true
                connectedDevices[idx].lastUpdated = Date()
                
                // If we can get battery from IOBluetooth KVC - set it
                if let p = d.bd_batteryPercent {
                    connectedDevices[idx].batteryPercent = p
                }
            } else {
                connectedDevices.append(
                    DeviceBatteryInfo(
                        id: id,
                        name: name,
                        batteryPercent: d.bd_batteryPercent,
                        lastUpdated: Date(),
                        isConnected: true
                    )
                )
            }
        }
        
        // remove devices that are not connected anymore (optional; can keep but hide in UI)
        connectedDevices.removeAll { !$0.isConnected }
    }
    
    // MARK: - BLE (fallback)
    
    private func handleConnectedBLEPeripherals(_ connected: [CBPeripheral]) {
        for p in connected {
            peripherals[p.identifier] = p
            p.delegate = self
            if p.state != .connected {
                central.connect(p, options: nil)
            } else {
                p.discoverServices([Self.batteryService])
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension DevicesBatteryViewModel: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                // Do a passive refresh (retrieve connected peripherals)
                let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
                handleConnectedBLEPeripherals(connected)
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String : Any],
                                    rssi RSSI: NSNumber) {
        // not used (we don't actively scan)
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // ignore
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            peripherals.removeValue(forKey: peripheral.identifier)
            batteryChars.removeValue(forKey: peripheral.identifier)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension DevicesBatteryViewModel: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        guard let services = peripheral.services else { return }
        
        for s in services where s.uuid == Self.batteryService {
            peripheral.discoverCharacteristics([Self.batteryLevelChar], for: s)
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        guard error == nil else { return }
        
        Task { @MainActor in
            guard let chars = service.characteristics else { return }
            
            for c in chars where c.uuid == Self.batteryLevelChar {
                self.batteryChars[peripheral.identifier] = c
                peripheral.readValue(for: c)
                peripheral.setNotifyValue(true, for: c)
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard error == nil else { return }
        guard characteristic.uuid == Self.batteryLevelChar else { return }
        guard let data = characteristic.value, data.count >= 1 else { return }
        
        let percent = Int(data.first!)
        
        Task { @MainActor in
            let name = (peripheral.name ?? "BLE device").trimmingCharacters(in: .whitespacesAndNewlines)
            let id = peripheral.identifier.uuidString
            
            if let idx = connectedDevices.firstIndex(where: { $0.id == id }) {
                connectedDevices[idx].name = name
                connectedDevices[idx].batteryPercent = percent
                connectedDevices[idx].lastUpdated = Date()
                connectedDevices[idx].isConnected = true
            } else {
                connectedDevices.append(
                    DeviceBatteryInfo(
                        id: id,
                        name: name,
                        batteryPercent: percent,
                        lastUpdated: Date(),
                        isConnected: true
                    )
                )
            }
        }
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
