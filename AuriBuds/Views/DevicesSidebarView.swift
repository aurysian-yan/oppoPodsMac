import SwiftUI

enum AuriBudsPreferenceKey {
    static let showsUnavailableDevices = "showsUnavailableDevices"
    static let statusBarDevicePriority = "statusBarDevicePriority"
}

struct StatusBarPriority {
    static func load() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: AuriBudsPreferenceKey.statusBarDevicePriority),
              let addresses = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return addresses
    }

    static func save(_ addresses: [String]) {
        guard let data = try? JSONEncoder().encode(addresses) else { return }
        UserDefaults.standard.set(data, forKey: AuriBudsPreferenceKey.statusBarDevicePriority)
    }
}

struct DevicesSidebarView: View {
    @ObservedObject var viewModel: EarbudsViewModel
    @Binding var currentPage: MainWindowPage
#if DEBUG
    @ObservedObject var testDeviceStore: DebugTestDeviceStore
#endif
    let errorLogCount: Int
    @AppStorage(AuriBudsPreferenceKey.showsUnavailableDevices) private var showsUnavailableDevices = true

    private var devices: [PairedDevice] {
#if DEBUG
        let allDevices = viewModel.availableDisplayDevices(testDevices: testDeviceStore.devices)
#else
        let allDevices = viewModel.pairedDevices
#endif

        guard showsUnavailableDevices else {
            return allDevices.filter(\.isAppControllable)
        }

        return allDevices
    }

    var body: some View {
        List {
            Section() {
                ForEach(devices) { device in
                    DeviceSidebarRow(
                        device: device,
                        connectionStatus: connectionStatus(for: device),
                        isSelected: currentPage == .device(device.id)
                    ) {
                        select(.device(device.id))
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: -8, bottom: 4, trailing: -8))
                    .listRowBackground(Color.clear)
                }
            } header: {
                Text("已配对的设备")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .padding(.bottom, 6)
            }
            .padding(.bottom, -4)
            
            Section() {
                SidebarNavigationRow(
                    title: "日志",
                    systemImage: "doc.text",
                    badgeCount: errorLogCount,
                    isSelected: currentPage == .logs
                ) {
                    select(.logs)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: -8, bottom: 4, trailing: -8))
                .listRowBackground(Color.clear)
                
                SidebarNavigationRow(
                    title: "设置",
                    systemImage: "gearshape",
                    isSelected: currentPage == .settings
                ) {
                    select(.settings)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: -8, bottom: 4, trailing: -8))
                .listRowBackground(Color.clear)
                
                
                Button {
                    viewModel.writeWidgetDebugData()
                } label: {
                    Label("Widget 调试写入", systemImage: "ladybug")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 4, trailing: 8))
                .listRowBackground(Color.clear)
            } header: {
                Rectangle()
#if os(macOS)
                    .fill(Color(nsColor: .separatorColor))
#else
                    .fill(Color(uiColor: .separator))
#endif
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.leading, 0)
                    .padding(.trailing, 10)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("设备")
    }

    private func select(_ page: MainWindowPage) {
        withAnimation(.snappy(duration: 0.24)) {
            currentPage = page
        }
    }

    private func connectionStatus(for device: PairedDevice) -> ConnectionStatus {
        if let connectionStatusOverride = device.connectionStatusOverride {
            return connectionStatusOverride
        }

        guard device.isAppControllable else {
            return .disconnected
        }

        if device.id == PairedDevice(state: viewModel.state).id {
            return viewModel.state.connectionStatus
        }

        return .disconnected
    }
}

private struct SidebarNavigationRow: View {
    let title: String
    let systemImage: String
    var badgeCount = 0
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Label {
                    Text(title)
                        .font(.system(size: 14).weight(.semibold))
                } icon: {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .center)
                }

                Spacer()

                if badgeCount > 0 {
                    Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                        .font(.system(size: 12).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(.red, in: Capsule())
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectionBackground, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectionBackground: Color {
#if os(macOS)
        isSelected ? Color.primary.opacity(0.10) : Color.clear
#else
        Color.clear
#endif
    }
}

private struct DeviceSidebarRow: View {
    @EnvironmentObject private var viewModel: EarbudsViewModel
    let device: PairedDevice
    let connectionStatus: ConnectionStatus
    let isSelected: Bool
    let action: () -> Void
    private var imageName: String? {
        device.selectedImageName ?? device.defaultImageName
    }

    @State private var blinkStatusDot = false

    private var statusDotColor: Color {
        switch connectionStatus {
        case .connected:
            return .green
        case .disconnected:
            return .secondary
        case .connecting, .handshaking, .reconnecting:
            return .accentColor
        case .error, .handshakeFailed, .deviceNotFound:
            return .red
        }
    }

    private var shouldBlinkStatusDot: Bool {
        switch connectionStatus {
        case .connecting, .handshaking, .reconnecting:
            return true
        default:
            return false
        }
    }

    private var statusTitle: String {
        if device.connectionStatusOverride != nil {
            return connectionStatus.localizedTitle
        }

        return connectionStatus.localizedTitle
    }

    init(
        device: PairedDevice,
        connectionStatus: ConnectionStatus,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.device = device
        self.connectionStatus = connectionStatus
        self.isSelected = isSelected
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        if device.isAppControllable {
            Button(action: action) {
                rowContent
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("刷新电量") {
                    Task {
                        await viewModel.refreshBattery()
                    }
                }
                .disabled(!canRefreshBattery)

                Button("重连") {
                    Task {
                        await viewModel.connect(device: device)
                    }
                }
                .disabled(viewModel.isBusy)

                Button("连接") {
                    Task {
                        await viewModel.connect(device: device)
                    }
                }
                .disabled(!canConnect)
            }
        } else {
            unavailableRowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            HStack() {
                DeviceImageView(
                    imageName: imageName,
                    fallbackSystemName: device.fallbackSystemName,
                    size: CGSize(width: 38, height: 38)
                )
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.system(size: 15))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    statusDot

                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(connectionStatus == .connected ? .green : .secondary)
                }
            }

            Spacer()
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionBackground, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    private var unavailableRowContent: some View {
        HStack(spacing: 10) {
            DeviceImageView(
                imageName: imageName,
                fallbackSystemName: device.fallbackSystemName,
                size: CGSize(width: 30, height: 30)
            )
            .frame(width: 50, height: 38)

            Text(device.displayName)
                .font(.system(size: 14))
                .strikethrough(true, color: .secondary)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()
        }
        .opacity(0.55)
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(width: 6, height: 6)
            .opacity(shouldBlinkStatusDot ? (blinkStatusDot ? 0.25 : 1.0) : 1.0)
            .animation(
                shouldBlinkStatusDot ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : nil,
                value: blinkStatusDot
            )
            .onAppear {
                updateBlinking(isBlinking: shouldBlinkStatusDot)
            }
            .onChange(of: shouldBlinkStatusDot) { _, isBlinking in
                updateBlinking(isBlinking: isBlinking)
            }
    }

    private var selectionBackground: Color {
#if os(macOS)
        isSelected ? Color.primary.opacity(0.10) : Color.clear
#else
        Color.clear
#endif
    }

    private var canRefreshBattery: Bool {
        device.id == PairedDevice(state: viewModel.state).id &&
            viewModel.state.connectionStatus == .connected &&
            !viewModel.isBusy
    }

    private var canConnect: Bool {
        guard !viewModel.isBusy else { return false }
        guard device.isAppControllable else { return false }

        switch viewModel.state.connectionStatus {
        case .disconnected, .error, .handshakeFailed, .deviceNotFound:
            return true
        case .connected, .connecting, .handshaking, .reconnecting:
            return device.id != PairedDevice(state: viewModel.state).id
        }
    }

    private func updateBlinking(isBlinking: Bool) {
        blinkStatusDot = isBlinking
    }
}

private struct DevicesSidebarPreview: View {
    @StateObject private var viewModel = EarbudsViewModel()
    @State private var currentPage: MainWindowPage = .home

    var body: some View {
        Group {
#if DEBUG
            DevicesSidebarView(
                viewModel: viewModel,
                currentPage: $currentPage,
                testDeviceStore: DebugTestDeviceStore.shared,
                errorLogCount: 2
            )
#else
            DevicesSidebarView(
                viewModel: viewModel,
                currentPage: $currentPage,
                errorLogCount: 2
            )
#endif
        }
        .environmentObject(viewModel)
        .frame(width: 280, height: 560)
    }
}

#Preview {
    DevicesSidebarPreview()
}
