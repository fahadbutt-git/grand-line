import AppKit
import Foundation
import SwiftUI
import DenDenKit

/// The state of one panel (one per display that shows Den Den).
@MainActor
final class NotchModel: ObservableObject {
    @Published var isOpen = false
    /// Artwork and playing bars beside the closed notch.
    @Published var showsLiveActivity = false
    /// System Settings, Accessibility, Display, Reduce motion.
    @Published var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @Published private(set) var screen: ScreenInfo
    @Published private(set) var style: PanelStyle
    @Published private(set) var content = PanelContent(sections: 0, userWidgets: 0)

    /// Asked by the view when the panel is tapped.
    var onTap: (@MainActor () -> Void)?

    init(screen: ScreenInfo, style: PanelStyle) {
        self.screen = screen
        self.style = style
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
        NotchGeometry.collapsedPanelSize(of: screen, liveActivity: showsLiveActivity)
    }

    var expandedPanelSize: CGSize {
        NotchGeometry.expandedSize(of: screen, content: content)
    }

    var currentSize: CGSize { isOpen ? expandedPanelSize : collapsedPanelSize }

    func frame(open: Bool) -> CGRect {
        NotchGeometry.topCentred(open ? expandedPanelSize : collapsedPanelSize, on: screen)
    }
}
