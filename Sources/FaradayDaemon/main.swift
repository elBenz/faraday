import CoreBluetooth
import Darwin
import FaradayCore
import Foundation

final class CoreBluetoothIBeaconBridge: NSObject, CBCentralManagerDelegate {
    private let core: FaradayCore
    private var central: CBCentralManager!

    init(core: FaradayCore) {
        self.core = core
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth powered on; scanning for iBeacon advertisements")
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        case .poweredOff:
            print("Bluetooth powered off; beacon scanning stopped")
        case .unauthorized:
            print("Bluetooth unauthorized; grant Bluetooth access to FaradayDaemon or Terminal")
        case .unsupported:
            print("Bluetooth unsupported on this Mac")
        case .resetting:
            print("Bluetooth resetting")
        case .unknown:
            print("Bluetooth state unknown")
        @unknown default:
            print("Bluetooth state unhandled: \(central.state.rawValue)")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            return
        }
        _ = core.ingestIBeaconScan(manufacturerData: manufacturerData, rssi: RSSI.intValue)
    }
}

let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
let baseDirectory = homeDirectory.appendingPathComponent(".faraday", isDirectory: true)
let persistence = JSONFaradayPersistence(baseDirectoryURL: baseDirectory)
let executablePath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let helperPath = executablePath.deletingLastPathComponent().appendingPathComponent("FaradayOverlayHelper").path
let overlay = ProcessOverlayAdapter(helperExecutablePath: helperPath)
let core = FaradayCore(overlay: overlay, persistence: persistence)
let bluetoothBridge = CoreBluetoothIBeaconBridge(core: core)
let rpc = FaradayRPCService(core: core)
let socketURL = baseDirectory.appendingPathComponent("faraday.sock")

try? FileManager.default.removeItem(at: socketURL)

let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
guard serverFD >= 0 else {
    fatalError("Failed to create UNIX socket")
}

var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
let path = socketURL.path
let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
guard path.utf8.count < maxPathLength else {
    close(serverFD)
    fatalError("Socket path too long: \(path)")
}

withUnsafeMutablePointer(to: &address.sun_path) { ptr in
    path.withCString { src in
        _ = strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), src, maxPathLength - 1)
    }
}

let bindResult = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}

guard bindResult == 0 else {
    close(serverFD)
    fatalError("Failed to bind UNIX socket at \(path)")
}

guard listen(serverFD, 16) == 0 else {
    close(serverFD)
    fatalError("Failed to listen on UNIX socket")
}

atexit {
    close(serverFD)
    try? FileManager.default.removeItem(at: socketURL)
}

print("Faraday daemon core started")
print("State: \(core.readStatus().sessionState) | Enforcement: \(core.readStatus().enforcementMode)")
print("Persistence directory: \(baseDirectory.path)")
print("RPC socket: \(socketURL.path)")
print("Press Ctrl+C to stop")

DispatchQueue.global(qos: .userInitiated).async {
    while true {
        let clientFD = accept(serverFD, nil, nil)
        if clientFD < 0 {
            continue
        }

        var requestBuffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = read(clientFD, &chunk, chunk.count)
            if count <= 0 {
                break
            }

            requestBuffer.append(chunk, count: count)

            if chunk.prefix(count).contains(10) { // newline-delimited JSON-RPC
                break
            }
        }

        if let newline = requestBuffer.firstIndex(of: 10) {
            requestBuffer = requestBuffer.prefix(upTo: newline)
        }

        if !requestBuffer.isEmpty, let response = rpc.handle(requestData: requestBuffer) {
            _ = response.withUnsafeBytes {
                Darwin.write(clientFD, $0.baseAddress, response.count)
            }
            _ = Darwin.write(clientFD, "\n", 1)
        }

        close(clientFD)
    }
}

RunLoop.main.run()
