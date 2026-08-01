import Foundation

enum XiaomiFrameParser {
    static func decodeBattery(from data: Data) -> BatteryState? {
        for packet in XiaomiRCSPFrame.decodeAll(data) where packet.opcode == XiaomiRCSPCommand.getTargetInfo {
            if let battery = decodeBatteryFromTargetInfoPayload(packet.parameter)
                ?? decodeBatteryFromLoosePayload(packet.parameter) {
                return battery
            }
        }

        return decodeBatteryFromLoosePayload(Array(data))
    }

    static func isBatteryResponse(_ data: Data) -> Bool {
        decodeBattery(from: data) != nil
    }

    static func decodeANCMode(from data: Data) -> ANCMode? {
        for packet in XiaomiRCSPFrame.decodeAll(data) {
            if packet.opcode == XiaomiRCSPCommand.getDeviceConfig,
               let mode = decodeANCMode(fromDeviceConfigPayload: packet.parameter) {
                return mode
            }

            if let mode = decodeANCMode(fromVendorPayload: packet.parameter) {
                return mode
            }
        }

        let bytes = Array(data)
        return decodeANCMode(fromDeviceConfigPayload: bytes)
            ?? decodeANCMode(fromVendorPayload: bytes)
    }

    static func isANCResponse(_ data: Data) -> Bool {
        decodeANCMode(from: data) != nil
    }

    private static func decodeBatteryFromTargetInfoPayload(_ payload: [UInt8]) -> BatteryState? {
        decodeBatteryFromTargetInfoTLV(payload)
            ?? decodeBatteryTriplet(payload)
    }

    private static func decodeBatteryFromTargetInfoTLV(_ payload: [UInt8]) -> BatteryState? {
        var index = 0

        while index + 1 < payload.count {
            let length = Int(payload[index])
            let recordEnd = index + 1 + length
            guard length > 0, recordEnd <= payload.count else {
                index += 1
                continue
            }

            let type = payload[index + 1]
            let valueStart = index + 2
            if type == 0x07, valueStart + 3 <= recordEnd {
                let triplet = Array(payload[valueStart..<(valueStart + 3)])
                if let battery = decodeBatteryTriplet(triplet) {
                    return battery
                }
            }

            index = recordEnd
        }

        return nil
    }

    private static func decodeBatteryTriplet(_ bytes: [UInt8]) -> BatteryState? {
        guard bytes.count >= 3 else { return nil }
        let triplet = Array(bytes[0..<3])
        guard triplet.allSatisfy({ $0 != 0xFF }) else { return nil }
        guard triplet.allSatisfy({ ($0 & 0x7F) <= 100 }) else { return nil }

        return BatteryState(
            left: triplet[0],
            right: triplet[1],
            batteryCase: triplet[2]
        )
    }

    private static func decodeBatteryFromLoosePayload(_ bytes: [UInt8]) -> BatteryState? {
        guard bytes.count >= 3 else { return nil }

        for index in 0...(bytes.count - 3) {
            let candidate = Array(bytes[index..<(index + 3)])
            guard candidate.allSatisfy({ ($0 & 0x7F) <= 100 }) else { continue }
            let hasRealisticBattery = candidate.contains { (1...100).contains(Int($0 & 0x7F)) }
            guard hasRealisticBattery else { continue }

            return BatteryState(
                left: candidate[0],
                right: candidate[1],
                batteryCase: candidate[2]
            )
        }

        return nil
    }

    private static func decodeANCMode(fromDeviceConfigPayload bytes: [UInt8]) -> ANCMode? {
        var index = 0

        while index + 3 < bytes.count {
            let length = Int(bytes[index])
            let recordEnd = index + 1 + length
            guard length >= 3, recordEnd <= bytes.count else {
                index += 1
                continue
            }

            let type = (Int(bytes[index + 1]) << 8) | Int(bytes[index + 2])
            if type == 0x000B, let mode = ancMode(for: bytes[index + 3]) {
                return mode
            }

            index = recordEnd
        }

        return nil
    }

    private static func decodeANCMode(fromVendorPayload bytes: [UInt8]) -> ANCMode? {
        guard bytes.count >= 3 else { return nil }

        for index in 0...(bytes.count - 3) {
            let length = Int(bytes[index])
            guard length >= 2 else { continue }
            let typeIndex = index + 1
            let valueIndex = index + 2
            guard valueIndex < bytes.count, bytes[typeIndex] == 0x04 else { continue }

            if let mode = ancMode(for: bytes[valueIndex]) {
                return mode
            }
        }

        return nil
    }

    private static func ancMode(for value: UInt8) -> ANCMode? {
        switch value {
        case 0x00:
            return .off
        case 0x01:
            return .noiseCancellation
        case 0x02:
            return .transparency
        default:
            return nil
        }
    }
}
