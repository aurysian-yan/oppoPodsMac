#if os(macOS)
import AppKit
import SwiftUI

@main
struct AuriBudsApp: App {
    @StateObject private var viewModel = EarbudsViewModel()
    @State private var appeared = false
    
    init() {
        BluetoothMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup("", id: "main") {
            MainWindowView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.start()
                }
        }
        .defaultSize(width: 768, height: 720)
        .commands {
            CommandMenu("设备") {
                Button("刷新电量") {
                    Task {
                        await viewModel.refreshBattery()
                    }
                }
                .disabled(!canRefreshBattery)

                Button("重连") {
                    Task {
                        await viewModel.reconnect()
                    }
                }
                .disabled(viewModel.isBusy)

                Button("连接") {
                    Task {
                        await viewModel.connect()
                    }
                }
                .disabled(!canConnect)
            }
        }

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.start()
                }
        } label: {
            Image("projectlogo.large")
                .renderingMode(.template)
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)
                .animation(
                    .spring(response: 0.4),
                    value: appeared
                )
                .onAppear {
                    appeared = true
                }
        }
        .menuBarExtraStyle(.window)
    }

    private var canRefreshBattery: Bool {
        viewModel.state.connectionStatus == .connected && !viewModel.isBusy
    }

    private var canConnect: Bool {
        guard !viewModel.isBusy else { return false }

        switch viewModel.state.connectionStatus {
        case .disconnected, .error, .handshakeFailed, .deviceNotFound:
            return true
        case .connected, .connecting, .handshaking, .reconnecting:
            return false
        }
    }
}

#Preview {
    MainWindowView()
        .environmentObject(EarbudsViewModel())
}
#endif
