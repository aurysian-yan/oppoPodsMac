import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
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

    func save() {
        Self.logger.debug("[SAVE] begin suite=\(Self.appGroupSuite) key=\(Self.storageKey)")

        guard let data = try? JSONEncoder().encode(self) else {
            Self.logger.error("[SAVE] FAIL — JSONEncoder.encode failed")
            assertionFailure("WidgetHeadphoneData.save: encoding failed")
            return
        }
        Self.logger.debug("[SAVE] encoded \(data.count) bytes | name=\(self.deviceName, privacy: .public) status=\(self.connectionStatus, privacy: .public) L=\(self.batteryLeft, privacy: .public) R=\(self.batteryRight, privacy: .public) C=\(self.batteryCase, privacy: .public)")

        guard let store = UserDefaults(suiteName: Self.appGroupSuite) else {
            Self.logger.fault("[SAVE] FAIL — UserDefaults(suiteName:) nil for \(Self.appGroupSuite)")
            assertionFailure("WidgetHeadphoneData.save: App Group \(Self.appGroupSuite) unavailable")
            return
        }

        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupSuite)
        Self.logger.debug("[SAVE] containerPath=\(containerURL?.path ?? "nil", privacy: .public)")

        store.set(data, forKey: Self.storageKey)

        if let readBack = store.data(forKey: Self.storageKey) {
            let match = readBack == data
            Self.logger.debug("[SAVE] verify readBack: \(readBack.count) bytes, match=\(match)")
            if !match {
                Self.logger.error("[SAVE] FAIL — verify: DATA MISMATCH")
                assertionFailure("WidgetHeadphoneData.save: write-verify data mismatch")
            }
        } else {
            Self.logger.error("[SAVE] FAIL — verify: readBack nil")
            assertionFailure("WidgetHeadphoneData.save: write-verify readBack nil")
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        Self.logger.debug("[SAVE] reloadAllTimelines called")
        WidgetCenter.shared.reloadTimelines(ofKind: "top.aurysian.auribuds.AuriBudsWidget")
        Self.logger.debug("[SAVE] reloadTimelines(ofKind:) called")
        #endif
    }
}
