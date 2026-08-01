import Foundation
#if os(macOS)
import IOBluetooth
#else
typealias BluetoothRFCOMMChannelID = UInt8
#endif

struct HeadphoneAdapterProfile: Equatable {
    let rfcommChannelIDs: [BluetoothRFCOMMChannelID]
}

protocol HeadphoneManaging: AnyObject {
    var onEvent: ((String) -> Void)? { get set }

    func connect(deviceName: String) async throws -> BatteryState
    func connect(device: BluetoothDeviceSnapshot) async throws -> BatteryState
    func disconnect() async
    func refreshBattery(deviceName: String) async throws -> BatteryState
    func refreshBattery(device: BluetoothDeviceSnapshot) async throws -> BatteryState
    func refreshANC(deviceName: String) async throws -> ANCMode
    func refreshANC(device: BluetoothDeviceSnapshot) async throws -> ANCMode
    func setANC(_ mode: ANCMode, deviceName: String) async throws
    func setANC(_ mode: ANCMode, device: BluetoothDeviceSnapshot) async throws

    func isBatteryDecodeFailure(_ error: Error) -> Bool
    func isHandshakeFailure(_ error: Error) -> Bool
    func isDeviceNotFound(_ error: Error) -> Bool
    func isCommandTimeout(_ error: Error) -> Bool
}

protocol HeadphoneAdapter {
    var id: String { get }
    var displayName: String { get }

    func canControl(deviceName: String) -> Bool
    func profile(for deviceName: String) -> HeadphoneAdapterProfile
    func makeManager() -> any HeadphoneManaging
}

final class HeadphoneAdapterRegistry {
    static let shared = HeadphoneAdapterRegistry(adapters: [XiaomiHeadphoneAdapter(), OppoHeadphoneAdapter()])

    private let adapters: [any HeadphoneAdapter]

    private init(adapters: [any HeadphoneAdapter]) {
        self.adapters = adapters
    }

    func adapter(for snapshot: BluetoothDeviceSnapshot) -> (any HeadphoneAdapter)? {
        adapter(forDeviceName: snapshot.name)
    }

    func adapter(forDeviceName deviceName: String) -> (any HeadphoneAdapter)? {
        adapters.first { $0.canControl(deviceName: deviceName) }
    }

    func canControl(_ snapshot: BluetoothDeviceSnapshot) -> Bool {
        adapter(for: snapshot) != nil
    }

    func canControl(deviceName: String) -> Bool {
        adapter(forDeviceName: deviceName) != nil
    }

    func profile(for deviceName: String) -> HeadphoneAdapterProfile? {
        guard let adapter = adapter(forDeviceName: deviceName) else {
            return nil
        }
        return adapter.profile(for: deviceName)
    }
}

struct XiaomiHeadphoneAdapter: HeadphoneAdapter {
    let id = "xiaomi"
    let displayName = "Xiaomi / Redmi / POCO"

    func canControl(deviceName: String) -> Bool {
        XiaomiDeviceProfile.isLikelyXiaomiAudioDevice(deviceName)
    }

    func profile(for deviceName: String) -> HeadphoneAdapterProfile {
        let profile = XiaomiDeviceProfile.profile(for: deviceName)
        return HeadphoneAdapterProfile(rfcommChannelIDs: profile.channelIDs)
    }

    func makeManager() -> any HeadphoneManaging {
        XiaomiProtocol()
    }
}

struct OppoHeadphoneAdapter: HeadphoneAdapter {
    let id = "oppo"
    let displayName = "OPPO / OnePlus / realme"

    func canControl(deviceName: String) -> Bool {
        OppoDeviceProfile.isLikelyOppoAudioDevice(deviceName)
    }

    func profile(for deviceName: String) -> HeadphoneAdapterProfile {
        let profile = OppoDeviceProfile.profile(for: deviceName)
        return HeadphoneAdapterProfile(rfcommChannelIDs: profile.channelIDs)
    }

    func makeManager() -> any HeadphoneManaging {
        OppoProtocol()
    }
}

extension XiaomiProtocol: HeadphoneManaging {
    func isBatteryDecodeFailure(_ error: Error) -> Bool {
        (error as? XiaomiProtocolError) == .batteryDecodeFailed
    }

    func isHandshakeFailure(_ error: Error) -> Bool {
        (error as? XiaomiProtocolError) == .handshakeFailed
    }

    func isDeviceNotFound(_ error: Error) -> Bool {
        if isBluetoothLEDeviceNotFound(error) {
            return true
        }

        guard case .allTransportsFailed(let reason) = error as? XiaomiProtocolError else {
            return false
        }

        return reason.contains("No BLE device matched") || reason.contains("未发现设备")
    }

    func isCommandTimeout(_ error: Error) -> Bool {
        guard let error = error as? XiaomiProtocolError else { return false }
        if case .commandTimeout = error {
            return true
        }
        return false
    }
}

extension OppoProtocol: HeadphoneManaging {
    func isBatteryDecodeFailure(_ error: Error) -> Bool {
        (error as? OppoProtocolError) == .batteryDecodeFailed
    }

    func isHandshakeFailure(_ error: Error) -> Bool {
        (error as? OppoProtocolError) == .handshakeFailed
    }

    func isDeviceNotFound(_ error: Error) -> Bool {
        isBluetoothLEDeviceNotFound(error)
    }

    func isCommandTimeout(_ error: Error) -> Bool {
        guard let error = error as? OppoProtocolError else { return false }
        if case .commandTimeout = error {
            return true
        }
        return false
    }
}

private func isBluetoothLEDeviceNotFound(_ error: Error) -> Bool {
    if let error = error as? BluetoothLETransportError {
        switch error {
        case .deviceNotFound:
            return true
        default:
            return false
        }
    }

#if os(macOS)
    if let error = error as? BluetoothTransportError {
        switch error {
        case .deviceNotFound:
            return true
        }
    }
#endif

    if let error = error as? XiaomiBLETransportError {
        switch error {
        case .deviceNotFound:
            return true
        default:
            return false
        }
    }

    let description = error.localizedDescription
    return description.contains("No BLE device matched")
        || description.contains("No Xiaomi BLE peripheral matched")
        || description.contains("No paired Bluetooth device matched")
        || description.contains("未发现设备")
}
