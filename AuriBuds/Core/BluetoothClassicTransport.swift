#if os(macOS)
import Foundation
import IOBluetooth

enum BluetoothTransportError: Error, LocalizedError {
    case deviceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "未发现设备"
        }
    }
}

final class BluetoothClassicTransport {
    private let openTimeout: TimeInterval
    private let closeTimeout: TimeInterval
    private let retryDelay: TimeInterval
    private let maxAttempts: Int
    private var cachedDevice: IOBluetoothDevice?
    private var cachedDeviceIdentifier: String?

    init(
        openTimeout: TimeInterval = 5,
        closeTimeout: TimeInterval = 1.5,
        retryDelay: TimeInterval = 0.5,
        maxAttempts: Int = 2
    ) {
        self.openTimeout = openTimeout
        self.closeTimeout = closeTimeout
        self.retryDelay = retryDelay
        self.maxAttempts = maxAttempts
    }

    func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
    }

    func findDevice(named targetName: String) throws -> IOBluetoothDevice {
        try findDevice(identifier: targetName)
    }

    func findDevice(identifier: String) throws -> IOBluetoothDevice {
        if let cachedDevice,
           let cachedDeviceIdentifier,
           normalize(cachedDeviceIdentifier) == normalize(identifier) {
            return cachedDevice
        }

        let normalizedTarget = normalize(identifier)
        guard !normalizedTarget.isEmpty else {
            throw BluetoothTransportError.deviceNotFound(identifier)
        }

        if let device = pairedDevices().first(where: { device in
            normalize(device.name ?? "").contains(normalizedTarget)
                || normalize(device.addressString ?? "").contains(normalizedTarget)
        }) {
            cachedDevice = device
            cachedDeviceIdentifier = identifier
            return device
        }

        throw BluetoothTransportError.deviceNotFound(identifier)
    }

    func connect(deviceName: String, onEvent: @escaping (String) -> Void) throws -> SafeRfcommConnection {
        try connect(deviceIdentifier: deviceName, fallbackName: deviceName, onEvent: onEvent)
    }

    func connect(device: BluetoothDeviceSnapshot, onEvent: @escaping (String) -> Void) throws -> SafeRfcommConnection {
        try connect(
            deviceIdentifier: device.address.isEmpty ? device.name : device.address,
            fallbackName: device.name,
            onEvent: onEvent
        )
    }

    private func connect(
        deviceIdentifier: String,
        fallbackName: String,
        onEvent: @escaping (String) -> Void
    ) throws -> SafeRfcommConnection {
        let device = try findDevice(identifier: deviceIdentifier)
        let deviceName = device.name ?? fallbackName
        let profile = HeadphoneAdapterRegistry.shared.profile(for: deviceName)
        var channelIDs = profile?.rfcommChannelIDs ?? [15, 18, 12, 19]
        if XiaomiDeviceProfile.isLikelyXiaomiAudioDevice(deviceName) {
            channelIDs = mergeChannels(
                preferred: XiaomiDeviceProfile.preferredRFCOMMChannelIDs(for: device),
                fallback: channelIDs
            )
        }
        var lastError: Error?

        onEvent("device \(deviceName)")
        onEvent("rfcomm candidates \(channelIDs.map(String.init).joined(separator: ","))")

        for channelID in channelIDs {
            do {
                return try SafeRfcommConnection.connect(
                    device: device,
                    channelID: channelID,
                    maxAttempts: maxAttempts,
                    openTimeout: openTimeout,
                    closeTimeout: closeTimeout,
                    retryDelay: retryDelay,
                    onEvent: onEvent
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? BluetoothTransportError.deviceNotFound(deviceIdentifier)
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func mergeChannels(
        preferred: [BluetoothRFCOMMChannelID],
        fallback: [BluetoothRFCOMMChannelID]
    ) -> [BluetoothRFCOMMChannelID] {
        var seen = Set<BluetoothRFCOMMChannelID>()
        return (preferred + fallback).filter { seen.insert($0).inserted }
    }
}
#endif
