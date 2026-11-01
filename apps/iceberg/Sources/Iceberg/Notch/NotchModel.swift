import AppKit
import Foundation
import SwiftUI
import IcebergKit

/// The state of one panel (one per display that shows Iceberg).
@MainActor
final class NotchModel: ObservableObject {
    @Published var isOpen = false
    /// Artwork and playing bars beside the closed notch.
    @Published var showsLiveActivity = false
    /// A HUD (volume, brightness, battery, headphones) beside the closed notch.
    @Published var hud: HUDEvent?
    /// System Settings, Accessibility, Display, Reduce motion.
    @Published var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// Low Power Mode, and displays asleep: the playing bars rest then.
    @Published private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var displaysAsleep = false
    private var powerObservers: [NSObjectProtocol] = []
    @Published private(set) var screen: ScreenInfo
    @Published private(set) var style: PanelStyle
    @Published private(set) var content = PanelContent(sections: 0, userWidgets: 0)

    /// Asked by the view when the panel is tapped.
    var onTap: (@MainActor () -> Void)?

    init(screen: ScreenInfo, style: PanelStyle) {
        self.screen = screen
        self.style = style
        let workspace = NSWorkspace.shared.notificationCenter
        powerObservers = [
            NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
            },
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.displaysAsleep = true }
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.displaysAsleep = false }
            },
        ]
    }

    deinit {
        for observer in powerObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Whether the closed notch's playing bars move (`WakePolicy.barsMove`).
    func barsMove(playing: Bool) -> Bool {
        WakePolicy.barsMove(playing: playing, reduceMotion: reduceMotion, lowPower: lowPower, displaysAsleep: displaysAsleep)
    }

    func update(screen: ScreenInfo, style: PanelStyle) {
        if screen != self.screen { self.screen = screen }
        if style != self.style { self.style = style }
    }

    func update(content: PanelContent) {
        if content != self.content { self.content = content }
    }

    /// The closed notch's height (also the height of the open panel's top band).
    var bandHeight: CGFloat { NotchGeometry.collapsedSize(of: screen).height }
    /// The camera housing's width, which nothing is drawn under.
    var cameraWidth: CGFloat { style == .notch ? NotchGeometry.collapsedSize(of: screen).width : 0 }

    var collapsedPanelSize: CGSize {
        if hud != nil { return NotchGeometry.hudPanelSize(of: screen) }
        return NotchGeometry.collapsedPanelSize(of: screen, liveActivity: showsLiveActivity)
    }

    var expandedPanelSize: CGSize {
        NotchGeometry.expandedSize(of: screen, content: content)
    }

    var currentSize: CGSize { isOpen ? expandedPanelSize : collapsedPanelSize }

    func frame(open: Bool) -> CGRect {
        NotchGeometry.topCentred(open ? expandedPanelSize : collapsedPanelSize, on: screen)
    }
}
