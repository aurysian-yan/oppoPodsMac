#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class ConnectionPopupWindowController {
    static let shared = ConnectionPopupWindowController()

    private let size = NSSize(width: 320, height: 60)
    // 阴影模糊半径较大，需要足够的透明边距，否则柔和的胶囊阴影会被窗口的矩形边界裁切成直边，看起来像长方形。
    private let shadowPadding: CGFloat = 50
    private var panelSize: NSSize { NSSize(width: size.width + shadowPadding * 2, height: size.height + shadowPadding * 2) }
    private let state = ConnectionPopupState()
    private var panel: NSPanel?
    private var visualEffectView: NSVisualEffectView?
    private var hostingView: NSHostingView<ConnectionPopupView>?
    private var hideWorkItem: DispatchWorkItem?
    private var animationGeneration = 0

    private init() {}

    nonisolated func showConnected(deviceName: String, batteryLevel: Int?, imageName: String? = nil) {
        showConnectedIfNeeded(deviceName: deviceName, batteryLevel: batteryLevel, imageName: imageName)
    }

    nonisolated func showConnectedIfNeeded(deviceName: String, batteryLevel: Int?, imageName: String? = nil) {
        debugLog("showConnectedIfNeeded requested device=\(deviceName), battery=\(batteryLevel.map(String.init) ?? "nil"), mainThread=\(Thread.isMainThread)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.showConnectedOnMain(deviceName: deviceName, batteryLevel: batteryLevel, imageName: imageName)
        }
    }

    nonisolated func updateBatteryLevel(_ batteryLevel: Int?) {
        debugLog("updateBatteryLevel requested battery=\(batteryLevel.map(String.init) ?? "nil"), mainThread=\(Thread.isMainThread)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state.batteryLevel = batteryLevel
            self.debugLogOnMain("updateBatteryLevel applied battery=\(batteryLevel.map(String.init) ?? "nil")")
        }
    }

    nonisolated func hide() {
        debugLog("hide requested mainThread=\(Thread.isMainThread)")

        Task { @MainActor [weak self] in
            self?.hideOnMain()
        }
    }

    private func showConnectedOnMain(deviceName: String, batteryLevel: Int?, imageName: String?) {
        debugLogOnMain("showConnectedIfNeeded entered mainThread=\(Thread.isMainThread)")

        if hideWorkItem != nil {
            debugLogOnMain("cancel old hideWorkItem")
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil

        animationGeneration += 1
        let generation = animationGeneration

        let panel = panel ?? makePanel()
        if self.panel == nil {
            debugLogOnMain("panel created")
        } else {
            debugLogOnMain("panel reused isVisible=\(panel.isVisible), alpha=\(panel.alphaValue)")
        }
        self.panel = panel

        if hostingView == nil {
            let hostingView = NSHostingView(rootView: ConnectionPopupView(state: state))
            hostingView.frame = NSRect(origin: .zero, size: size)
            hostingView.autoresizingMask = [.width, .height]
            self.hostingView = hostingView

            if let visualEffectView {
                visualEffectView.addSubview(hostingView)
            } else {
                panel.contentView = hostingView
            }
            debugLogOnMain("hostingView created frame=\(hostingView.frame)")
        } else if let visualEffectView, let hostingView, !visualEffectView.subviews.contains(hostingView) {
            visualEffectView.addSubview(hostingView)
            debugLogOnMain("hostingView restored to panel")
        }

        state.deviceName = deviceName
        state.status = .connected
        state.batteryLevel = batteryLevel
        state.imageName = imageName ?? DeviceImageProvider.shared.pairImageName(modelName: deviceName)
        state.isHiding = false

        let screen = screenForPopup()
        let panelFrame = frame(on: screen)
        debugLogOnMain("screen frame=\(screen.frame), visibleFrame=\(screen.visibleFrame)")
        debugLogOnMain("panel target frame=\(panelFrame)")

        panel.setContentSize(panelSize)
        panel.contentView?.frame = NSRect(origin: .zero, size: panelSize)
        panel.setFrame(panelFrame, display: true)

        let shouldAnimateIn = !panel.isVisible || !state.isPresented
        if shouldAnimateIn {
            state.isPresented = false
            panel.alphaValue = 0
            debugLogOnMain("prepare show animation isPresented=false, alpha=0")
        } else {
            state.isPresented = true
            panel.alphaValue = 1
            debugLogOnMain("panel already visible, keep isPresented=true, alpha=1")
        }

        panel.displayIfNeeded()
        debugLogOnMain("displayIfNeeded executed contentFrame=\(panel.contentView?.frame.debugDescription ?? "nil")")

        panel.orderFrontRegardless()
        debugLogOnMain("orderFrontRegardless executed isVisible=\(panel.isVisible)")
        panel.order(.above, relativeTo: 0)
        debugLogOnMain("order above executed isVisible=\(panel.isVisible), frame=\(panel.frame), level=\(panel.level.rawValue)")

        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, generation == self.animationGeneration else {
                Self.debugLog("show animation skipped by generation change")
                return
            }

            withAnimation(.snappy(duration: 0.24)) {
                self.state.isPresented = true
            }
            self.debugLogOnMain("state.isPresented set true")

            if let panel {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1
                } completionHandler: {
                    Self.debugLog("show alpha animation completed alpha=\(panel.alphaValue), isVisible=\(panel.isVisible)")
                }
            }

            self.scheduleAutoHide(duration: 3)
        }
    }

    private func hideOnMain() {
        debugLogOnMain("hide entered mainThread=\(Thread.isMainThread)")

        if hideWorkItem != nil {
            debugLogOnMain("cancel hideWorkItem in hide")
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil

        guard let panel, panel.isVisible || state.isPresented else {
            state.isPresented = false
            state.isHiding = false
            state.imageName = nil
            debugLogOnMain("hide skipped no visible panel")
            return
        }

        animationGeneration += 1
        let generation = animationGeneration
        state.isHiding = true

        withAnimation(.snappy(duration: 0.2)) {
            state.isPresented = false
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, generation == self.animationGeneration else { return }
                panel?.orderOut(nil)
                self.state.isHiding = false
                self.state.imageName = nil
                self.debugLogOnMain("hide completed orderOut isVisible=\(panel?.isVisible ?? false)")
            }
        }
    }

    private func scheduleAutoHide(duration: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
        debugLogOnMain("hideWorkItem rebuilt duration=\(duration)")
    }

    private func makePanel() -> NSPanel {
        let panelSize = self.panelSize
        let panel = ConnectionPopupPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let shadowView = NSView(frame: NSRect(origin: .zero, size: panelSize))
        shadowView.wantsLayer = true
        shadowView.layer?.shadowColor = NSColor.black.cgColor
        shadowView.layer?.shadowOffset = CGSize(width: 0, height: -6)
        shadowView.layer?.shadowOpacity = 0.15
        shadowView.layer?.shadowRadius = 16
        shadowView.layer?.shadowPath = CGPath(
            roundedRect: NSRect(origin: CGPoint(x: shadowPadding, y: shadowPadding), size: size),
            cornerWidth: size.height / 2,
            cornerHeight: size.height / 2,
            transform: nil
        )

        let visualEffectView = NSVisualEffectView(frame: NSRect(origin: CGPoint(x: shadowPadding, y: shadowPadding), size: size))
        visualEffectView.material = .menu
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = size.height / 2
        visualEffectView.layer?.masksToBounds = true
        // 胶囊描边：细边框跟随圆角，强化与背景的分隔。
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.layer?.borderColor = NSColor.separatorColor.cgColor
        visualEffectView.autoresizingMask = []
        shadowView.addSubview(visualEffectView)
        self.visualEffectView = visualEffectView

        panel.contentView = shadowView
        return panel
    }

    private func frame(on screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let panelSize = self.panelSize
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2 - shadowPadding,
            y: visibleFrame.maxY - size.height - 16 - shadowPadding
        )
        return NSRect(origin: origin, size: panelSize)
    }

    private func screenForPopup() -> NSScreen {
        NSScreen.main ?? NSScreen.screens[0]
    }

    private nonisolated static func debugLog(_ message: String) {
        #if DEBUG
        print("[ConnectionPopup] \(message)")
        #endif
    }

    private nonisolated func debugLog(_ message: String) {
        Self.debugLog(message)
    }

    private func debugLogOnMain(_ message: String) {
        Self.debugLog(message)
    }
}

final class ConnectionPopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

#Preview {
    let state = ConnectionPopupState()
    state.deviceName = "OPPO Enco Air4 Pro"
    state.status = .connected
    state.imageName = DeviceImageProvider.shared.pairImageName(modelName: state.deviceName)
    state.isPresented = true

    return ConnectionPopupView(state: state)
        .padding()
}
#endif
