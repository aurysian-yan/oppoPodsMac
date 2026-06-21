import Foundation
import OSLog

struct WidgetHeadphoneData: Codable {
    let deviceName: String
    let connectionStatus: String
    let batteryLeft: String
    let batteryRight: String
    let batteryCase: String
    let ancMode: String
    let isCaseCharging: Bool
    let imageName: String?
    let fallbackSystemName: String

    static let appGroupSuite = "group.top.aurysian.auribuds"
    private static let storageKey = "widgetHeadphoneData"
    private static let logger = Logger(subsystem: "top.aurysian.auribuds", category: "WidgetData")

    private static var fallback: WidgetHeadphoneData {
        WidgetHeadphoneData(
            deviceName: "--",
            connectionStatus: "未连接",
            batteryLeft: "--",
            batteryRight: "--",
            batteryCase: "--",
            ancMode: "关闭",
            isCaseCharging: false,
            imageName: nil,
            fallbackSystemName: "headphones"
        )
    }

    func save() {
        Self.logger.debug("[SAVE-W] begin widget side")
        guard let data = try? JSONEncoder().encode(self) else {
            Self.logger.error("[SAVE-W] FAIL — encode failed")
            return
        }
        guard let store = UserDefaults(suiteName: Self.appGroupSuite) else {
            Self.logger.fault("[SAVE-W] FAIL — suite \(Self.appGroupSuite) unavailable")
            return
        }
        store.set(data, forKey: Self.storageKey)
        Self.logger.debug("[SAVE-W] done, \(data.count) bytes")
    }

    static func load() -> WidgetHeadphoneData {
        let heartbeatKey = "widgetHeartbeat"
        if let store = UserDefaults(suiteName: appGroupSuite) {
            store.set(Date().timeIntervalSince1970, forKey: heartbeatKey)
        }
        return WidgetHeadphoneData(
            deviceName: "WIDGET OK",
            connectionStatus: "HELLO",
            batteryLeft: "11%",
            batteryRight: "22%",
            batteryCase: "33%",
            ancMode: "TEST",
            isCaseCharging: false,
            imageName: nil,
            fallbackSystemName: "headphones"
        )
    }
}
