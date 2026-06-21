import AppIntents
import OSLog
import SwiftUI
import WidgetKit

struct OpenAuriBudsIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 AuriBuds"
    static var description: IntentDescription = "打开 AuriBuds 主程序切换降噪模式"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct Provider: TimelineProvider {
    private static let logger = Logger(subsystem: "top.aurysian.auribuds", category: "WidgetTimeline")

    func placeholder(in context: Context) -> HeadphoneEntry {
        Self.logger.debug("[PLACEHOLDER] called, family=\(String(describing: context.family))")
        let entry = HeadphoneEntry(date: Date(), data: WidgetHeadphoneData.load())
        return entry
    }

    func getSnapshot(in context: Context, completion: @escaping (HeadphoneEntry) -> Void) {
        Self.logger.debug("[SNAPSHOT] called, family=\(String(describing: context.family))")
        let entry = HeadphoneEntry(date: Date(), data: WidgetHeadphoneData.load())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadphoneEntry>) -> Void) {
        Self.logger.debug("[TIMELINE] called, family=\(String(describing: context.family))")
        let data = WidgetHeadphoneData.load()
        Self.logger.debug("[TIMELINE] data: name=\(data.deviceName) status=\(data.connectionStatus) L=\(data.batteryLeft) R=\(data.batteryRight) C=\(data.batteryCase)")
        let entry = HeadphoneEntry(date: Date(), data: data)
        let timeline = Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(120)))
        Self.logger.debug("[TIMELINE] returning entry, nextRefresh=+120s")
        completion(timeline)
    }
}

struct HeadphoneEntry: TimelineEntry {
    let date: Date
    let data: WidgetHeadphoneData
}

struct AuriBudsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry
    @State private var blinkStatusDot = false

    private var statusDotColor: Color {
        let s = entry.data.connectionStatus
        if s == "已连接" { return .green }
        if ["连接中", "握手中", "重连中"].contains(s) { return .accentColor }
        return .secondary
    }

    private var shouldBlinkStatusDot: Bool {
        ["连接中", "握手中", "重连中"].contains(entry.data.connectionStatus)
    }

    var body: some View {
        if family == .systemSmall {
            smallBody
        } else {
            mediumBody
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 5, height: 5)
                    .opacity(shouldBlinkStatusDot ? 0.5 : 1.0)

                Text(entry.data.connectionStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .contentTransition(.interpolate)
            }

            Text(entry.data.deviceName)
                .font(.caption.weight(.semibold))
                .fontWidth(.condensed)
                .lineLimit(2)
                .contentTransition(.interpolate)

            HStack(spacing: 8) {
                batteryLabel(side: "L", value: entry.data.batteryLeft)
                batteryLabel(side: "R", value: entry.data.batteryRight)
                batteryLabel(side: "仓", value: entry.data.batteryCase)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func batteryLabel(side: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(side)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 8, height: 8)
                        .opacity(shouldBlinkStatusDot ? (blinkStatusDot ? 0.25 : 1.0) : 1.0)
                        .onAppear {
                            updateBlinking(isBlinking: shouldBlinkStatusDot)
                        }
                        .onChange(of: shouldBlinkStatusDot) { _, isBlinking in
                            updateBlinking(isBlinking: isBlinking)
                        }

                    Text(entry.data.connectionStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentTransition(.interpolate)
                }

                Text(entry.data.deviceName)
                    .font(.system(size: 24, weight: .medium))
                    .fontWidth(.condensed)
                    .lineLimit(2)
                    .contentTransition(.interpolate)
            }

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "l.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Left")
                    Text(entry.data.batteryLeft)
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.trailing, 4)

                HStack(spacing: 4) {
                    Image(systemName: "r.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Right")
                    Text(entry.data.batteryRight)
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.trailing, 4)

                HStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image("oppobuds.case.fill")
                            .resizable()
                            .scaledToFit()
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .accessibilityLabel("Case")

                        if entry.data.isCaseCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("充电中")
                                .padding(.trailing, -4)
                        }
                    }
                    Text(entry.data.batteryCase)
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            
            ancButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var deviceImageView: some View {
        Group {
            if let imageName = entry.data.imageName, let nsImage = NSImage(named: imageName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: entry.data.fallbackSystemName)
                    .font(.system(size: 40))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 80, height: 80)
    }

    private var ancButtons: some View {
        let modes: [(String, String)] = [
            ("关闭", "oppobuds.anc.fill"),
            ("通透模式", "oppobuds.transparency.fill"),
            ("降噪", "oppobuds.anc.on.fill")
        ]

        return HStack(spacing: 0) {
            ForEach(modes, id: \.0) { title, imageName in
                Button(intent: OpenAuriBudsIntent()) {
                    VStack(spacing: 2) {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .padding(6)
                            .background(
                                entry.data.ancMode == title
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear
                            )
                            .clipShape(Capsule())
                        Text(title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func updateBlinking(isBlinking: Bool) {
        blinkStatusDot = false

        if isBlinking {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                blinkStatusDot = true
            }
        }
    }
}

struct AuriBudsWidget: Widget {
    let kind: String = "top.aurysian.auribuds.AuriBudsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AuriBudsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AuriBuds")
        .description("查看耳机连接状态和电量")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
