import Foundation

enum OppoFrameParser {
    private static let ancAckBytes: [UInt8] = [0xAA, 0x08, 0x00, 0x00, 0x04, 0x84, 0xF0, 0x01, 0x00, 0x00]

    static func decodeBattery(from data: Data) -> BatteryState? {
        let bytes = Array(data)
        guard bytes.count >= 4 else { return nil }

        for commandIndex in 0...(bytes.count - 3) where bytes[commandIndex] == 0x06 && bytes[commandIndex + 1] == 0x81 && bytes[commandIndex + 2] == 0xF0 {
            guard bytes[..<commandIndex].contains(0xAA) else { continue }

            if let fields = parseBatteryFields(in: bytes, after: commandIndex + 3) {
                return BatteryState(
                    left: fields.left,
                    right: fields.right,
                    batteryCase: fields.batteryCase
                )
            }

            return .unknown
        }

        return nil
    }

    static func isBatteryResponse(_ data: Data) -> Bool {
        decodeBattery(from: data) != nil
    }

    static func isANCCandidateFrame(_ data: Data) -> Bool {
        let bytes = Array(data)
        guard bytes.count >= 6, bytes.contains(0xAA) else { return false }
        guard !containsSequence(ancAckBytes, in: bytes) else { return true }

        for index in 0..<(bytes.count - 1) {
            if bytes[index] == 0x0C && bytes[index + 1] == 0x81 {
                return true
            }

            if bytes[index] == 0x04 && bytes[index + 1] == 0x02 {
                return true
            }
        }

        return false
    }

    static func isANCResponse(_ data: Data) -> Bool {
        isANCCandidateFrame(data)
    }

    static func isANCModeResponse(_ data: Data, modeValue: UInt8) -> Bool {
        let bytes = Array(data)
        guard bytes.count >= 6, bytes.contains(0xAA) else { return false }
        guard !containsSequence(ancAckBytes, in: bytes) else { return true }

        for index in 0..<(bytes.count - 1) {
            let isModeFrame = (bytes[index] == 0x0C && bytes[index + 1] == 0x81)
                || (bytes[index] == 0x04 && bytes[index + 1] == 0x02)
            guard isModeFrame else { continue }

            if containsANCModePayload(modeValue, in: bytes, from: index + 2) {
                return true
            }
        }

        return false
    }

    static func decodeANCMode(from data: Data) -> ANCMode? {
        let bytes = Array(data)
        guard bytes.count >= 6, bytes.contains(0xAA) else { return nil }

        if let queryMode = decodeANCQueryMode(from: bytes) {
            return queryMode
        }

        for index in 0..<(bytes.count - 1) {
            let isModeFrame = (bytes[index] == 0x0C && bytes[index + 1] == 0x81)
                || (bytes[index] == 0x04 && bytes[index + 1] == 0x02)
            guard isModeFrame else { continue }

            if containsANCModePayload(0x01, in: bytes, from: index + 2) {
                return .off
            }

            if containsANCModePayload(0x02, in: bytes, from: index + 2) {
                return .noiseCancellation
            }

            if containsANCModePayload(0x04, in: bytes, from: index + 2) {
                return .transparency
            }
        }

        return nil
    }

    private static func decodeANCQueryMode(from bytes: [UInt8]) -> ANCMode? {
        guard let payload = commandPayload(in: bytes, commandLow: 0x0C, commandHigh: 0x81),
              payload.count >= 3,
              payload[0] == 0x00,
              payload[1] == 0x01 else {
            return nil
        }

        return ancMode(from: payload[2])
    }

    private static func parseBatteryFields(in bytes: [UInt8], after startIndex: Int) -> (left: UInt8?, right: UInt8?, batteryCase: UInt8?)? {
        guard startIndex < bytes.count else { return nil }

        for index in startIndex..<bytes.count {
            let fieldCount = Int(bytes[index])
            guard (1...3).contains(fieldCount) else { continue }

            let fieldsStart = index + 1
            let fieldsEnd = fieldsStart + fieldCount * 2
            guard fieldsEnd <= bytes.count else { continue }

            var left: UInt8?
            var right: UInt8?
            var batteryCase: UInt8?
            var seenComponents = Set<UInt8>()
            var isValid = true

            for fieldIndex in stride(from: fieldsStart, to: fieldsEnd, by: 2) {
                let component = bytes[fieldIndex]
                let value = bytes[fieldIndex + 1]
                guard seenComponents.insert(component).inserted else {
                    isValid = false
                    break
                }

                switch component {
                case 0x01:
                    left = value
                case 0x02:
                    right = value
                case 0x03:
                    batteryCase = value
                default:
                    isValid = false
                }

                guard isValid else { break }
            }

            if isValid {
                return (left: left, right: right, batteryCase: batteryCase)
            }
        }

        return nil
    }

    private static func containsANCModePayload(_ modeValue: UInt8, in bytes: [UInt8], from startIndex: Int) -> Bool {
        guard startIndex <= bytes.count - 3 else { return false }

        for index in startIndex...(bytes.count - 3) where bytes[index] == 0x01 && bytes[index + 1] == 0x01 && bytes[index + 2] == modeValue {
            return true
        }

        return false
    }

    private static func ancMode(from modeValue: UInt8) -> ANCMode? {
        switch modeValue {
        case 0x01:
            return .off
        case 0x02:
            return .noiseCancellation
        case 0x04:
            return .transparency
        default:
            return nil
        }
    }

    private static func commandPayload(in bytes: [UInt8], commandLow: UInt8, commandHigh: UInt8) -> [UInt8]? {
        guard bytes.count >= 9 else { return nil }

        for index in 0...(bytes.count - 9) {
            guard bytes[index] == 0xAA,
                  bytes[index + 4] == commandLow,
                  bytes[index + 5] == commandHigh else {
                continue
            }

            let payloadLength = Int(bytes[index + 7]) | (Int(bytes[index + 8]) << 8)
            let payloadStart = index + 9
            let payloadEnd = payloadStart + payloadLength
            guard payloadEnd <= bytes.count else { continue }

            return Array(bytes[payloadStart..<payloadEnd])
        }

        return nil
    }

    private static func containsSequence(_ sequence: [UInt8], in bytes: [UInt8]) -> Bool {
        guard !sequence.isEmpty, sequence.count <= bytes.count else { return false }

        for index in 0...(bytes.count - sequence.count) {
            if Array(bytes[index..<(index + sequence.count)]) == sequence {
                return true
            }
        }

        return false
    }
}
