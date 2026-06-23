#if os(macOS)
import AppKit
import SwiftUI

enum ConnectionPopupStatus {
    case connected
    case disconnected

    var title: String {
        switch self {
        case .connected:
            return "已连接"
        case .disconnected:
            return "已断开"
        }
    }
}

@MainActor
final class ConnectionPopupState: ObservableObject {
    @Published var deviceName = ""
    @Published var status: ConnectionPopupStatus = .connected
    @Published var batteryLevel: Int?
    @Published var imageName: String?
    @Published var isPresented = false
    @Published var isHiding = false
}

struct ConnectionPopupView: View {
    @ObservedObject var state: ConnectionPopupState

    private var contentScale: CGFloat {
        if state.isPresented {
            return 1
        }

        return state.isHiding ? 0.98 : 0.96
    }

    private var contentOffset: CGFloat {
        if state.isPresented {
            return 0
        }

        return state.isHiding ? -6 : -8
    }

    private var popupImageName: String? {
        guard let imageName = state.imageName else { return nil }
        let provider = DeviceImageProvider.shared
        return provider.pairImageName(productId: nil, colorId: nil, modelName: state.deviceName)
            ?? imageName
    }

    var body: some View {
            ZStack {
                HStack {
                    DeviceImageView(
                        imageName: popupImageName,
                        fallbackSystemName: "headphones",
                        size: CGSize(width: 38, height: 38)
                    )
                    .frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 2)

                    VStack(alignment: .center, spacing: 2) {
                        Text(state.deviceName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .multilineTextAlignment(.center)

                        Text(state.status.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    HStack { }
                        .frame(width: 46, height: 46)
                }
                .padding(.horizontal, 14)
                .frame(width: 320, height: 60)
                .opacity(state.isPresented ? 1 : 0)
                .scaleEffect(contentScale)
                .offset(y: contentOffset)
                .animation(.snappy(duration: 0.24), value: state.isPresented)
                .animation(.snappy(duration: 0.2), value: state.isHiding)
            }
        }
}

#Preview {
    let state = ConnectionPopupState()
    state.deviceName = "OPPO Enco Air4 Pro"
    state.batteryLevel = 86
    state.imageName = DeviceImageProvider.shared.primaryImageName(modelName: state.deviceName)
    state.isPresented = true

    return ConnectionPopupView(state: state)
        .padding()
}
#endif
