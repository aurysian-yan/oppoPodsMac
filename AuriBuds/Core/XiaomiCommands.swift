import Foundation

struct XiaomiRCSPConstants {
    static let targetAppEarphone: UInt8 = 0x04
    static let framePrefix: [UInt8] = [0xFE, 0xDC, 0xBA]
    static let frameSuffix: UInt8 = 0xEF
}

enum XiaomiRCSPCommand {
    static let getTargetInfo: UInt8 = 0x02
    static let setTargetInfo: UInt8 = 0x08
    static let getDeviceConfig: UInt8 = 0xF3
}

struct XiaomiCommand {
    let name: String
    let bytes: [UInt8]
    let expectedResponse: XiaomiResponseMatcher
    let timeout: TimeInterval
    let retryCount: Int

    init(
        name: String,
        bytes: [UInt8],
        expectedResponse: XiaomiResponseMatcher,
        timeout: TimeInterval = 2,
        retryCount: Int = 0
    ) {
        self.name = name
        self.bytes = bytes
        self.expectedResponse = expectedResponse
        self.timeout = timeout
        self.retryCount = retryCount
    }

    var hexString: String {
        bytes.hexString
    }
}

enum XiaomiResponseMatcher: Equatable {
    case none
    case opcode(UInt8)
    case opcodeStatus(UInt8, UInt8, sequence: UInt8)
    case battery
    case anc

    func matches(_ data: Data) -> Bool {
        switch self {
        case .none:
            return true
        case .opcode(let opcode):
            return XiaomiRCSPFrame.decodeAll(data).contains { $0.opcode == opcode }
        case .opcodeStatus(let opcode, let status, let sequence):
            return XiaomiRCSPFrame.decodeAll(data).contains {
                !$0.isCommand
                    && $0.opcode == opcode
                    && $0.status == status
                    && $0.sequence == sequence
            }
        case .battery:
            return XiaomiFrameParser.decodeBattery(from: data) != nil
        case .anc:
            return XiaomiFrameParser.decodeANCMode(from: data) != nil
                || matchesSuccessfulOpcode(data, XiaomiRCSPCommand.setTargetInfo)
        }
    }

    func rejectedStatus(in data: Data) -> UInt8? {
        guard case .opcodeStatus(let opcode, let expectedStatus, let sequence) = self else {
            return nil
        }

        return XiaomiRCSPFrame.decodeAll(data).first {
            !$0.isCommand
                && $0.opcode == opcode
                && $0.sequence == sequence
                && $0.status != expectedStatus
        }?.status
    }

    private func matchesSuccessfulOpcode(_ data: Data, _ opcode: UInt8) -> Bool {
        XiaomiRCSPFrame.decodeAll(data).contains {
            !$0.isCommand && $0.opcode == opcode && ($0.status ?? 0) == 0
        }
    }
}

enum XiaomiRCSPFrame {
    static func encodeCommand(
        opcode: UInt8,
        sequence: UInt8,
        targetApp: UInt8 = XiaomiRCSPConstants.targetAppEarphone,
        parameter: [UInt8] = [],
        hasResponse: Bool = true
    ) -> [UInt8] {
        let flag = UInt8(0x80)
            | (hasResponse ? UInt8(0x40) : UInt8(0x00))
            | (targetApp & 0x07)
        let parameterLength = parameter.count + 1

        return XiaomiRCSPConstants.framePrefix
            + [flag, opcode, UInt8((parameterLength >> 8) & 0xFF), UInt8(parameterLength & 0xFF), sequence]
            + parameter
            + [XiaomiRCSPConstants.frameSuffix]
    }

    static func decode(_ data: Data) -> XiaomiRCSPPacket? {
        decodeAll(data).first
    }

    static func decodeAll(_ data: Data) -> [XiaomiRCSPPacket] {
        let bytes = Array(data)
        guard bytes.count >= 9 else { return [] }

        var packets: [XiaomiRCSPPacket] = []
        var startIndex = 0

        while startIndex <= bytes.count - 9 {
            guard bytes[startIndex] == XiaomiRCSPConstants.framePrefix[0],
                  bytes[startIndex + 1] == XiaomiRCSPConstants.framePrefix[1],
                  bytes[startIndex + 2] == XiaomiRCSPConstants.framePrefix[2] else {
                startIndex += 1
                continue
            }

            let bodyStart = startIndex + 3
            let flag = bytes[bodyStart]
            let opcode = bytes[bodyStart + 1]
            let parameterLength = (Int(bytes[bodyStart + 2]) << 8) | Int(bytes[bodyStart + 3])
            let frameEnd = bodyStart + 4 + parameterLength
            guard parameterLength > 0,
                  frameEnd < bytes.count,
                  bytes[frameEnd] == XiaomiRCSPConstants.frameSuffix else {
                startIndex += 1
                continue
            }

            let isCommand = (flag & 0x80) != 0
            let hasResponse = (flag & 0x40) != 0
            let targetApp = flag & 0x07
            let firstPayloadIndex = bodyStart + 4
            let firstPayloadByte = bytes[firstPayloadIndex]
            let payloadStart = firstPayloadIndex + 1
            let payload = payloadStart <= frameEnd - 1 ? Array(bytes[payloadStart..<frameEnd]) : []

            if isCommand {
                packets.append(XiaomiRCSPPacket(
                    opcode: opcode,
                    sequence: firstPayloadByte,
                    status: nil,
                    targetApp: targetApp,
                    isCommand: true,
                    hasResponse: hasResponse,
                    parameter: payload
                ))
            } else {
                let sequence: UInt8
                let status: UInt8
                if opcode == 0x01 {
                    status = firstPayloadByte
                    sequence = 0
                } else {
                    status = firstPayloadByte
                    sequence = payload.first ?? 0
                }

                packets.append(XiaomiRCSPPacket(
                    opcode: opcode,
                    sequence: sequence,
                    status: status,
                    targetApp: targetApp,
                    isCommand: false,
                    hasResponse: hasResponse,
                    parameter: payload.dropFirstIfNeeded()
                ))
            }

            startIndex = frameEnd + 1
        }

        return packets
    }
}

struct XiaomiRCSPPacket: Equatable {
    let opcode: UInt8
    let sequence: UInt8
    let status: UInt8?
    let targetApp: UInt8
    let isCommand: Bool
    let hasResponse: Bool
    let parameter: [UInt8]
}

enum XiaomiCommands {
    static func getTargetInfo(sequence: UInt8) -> XiaomiCommand {
        XiaomiCommand(
            name: "Xiaomi Get Target Info",
            bytes: XiaomiRCSPFrame.encodeCommand(
                opcode: XiaomiRCSPCommand.getTargetInfo,
                sequence: sequence,
                parameter: [0xFF, 0xFF, 0xFF, 0xFF]
            ),
            expectedResponse: .battery,
            timeout: 3,
            retryCount: 1
        )
    }

    static func queryANC(sequence: UInt8) -> XiaomiCommand {
        XiaomiCommand(
            name: "Xiaomi Query ANC",
            bytes: XiaomiRCSPFrame.encodeCommand(
                opcode: XiaomiRCSPCommand.getDeviceConfig,
                sequence: sequence,
                parameter: [0x00, 0x0B]
            ),
            expectedResponse: .anc,
            timeout: 2,
            retryCount: 1
        )
    }

    static func setANC(_ mode: ANCMode, sequence: UInt8) -> XiaomiCommand {
        XiaomiCommand(
            name: "Xiaomi Set ANC \(mode.rawValue)",
            bytes: XiaomiRCSPFrame.encodeCommand(
                opcode: XiaomiRCSPCommand.setTargetInfo,
                sequence: sequence,
                parameter: vendorData(type: 0x04, data: [ancValue(for: mode)])
            ),
            expectedResponse: .opcodeStatus(XiaomiRCSPCommand.setTargetInfo, 0x00, sequence: sequence),
            timeout: 2,
            retryCount: 1
        )
    }

    private static func vendorData(type: UInt8, data: [UInt8]) -> [UInt8] {
        [UInt8(data.count + 1), type] + data
    }

    private static func ancValue(for mode: ANCMode) -> UInt8 {
        switch mode {
        case .off:
            return 0x00
        case .noiseCancellation:
            return 0x01
        case .transparency:
            return 0x02
        }
    }
}

private extension Array where Element == UInt8 {
    func dropFirstIfNeeded() -> [UInt8] {
        guard !isEmpty else { return [] }
        return Array(dropFirst())
    }
}
