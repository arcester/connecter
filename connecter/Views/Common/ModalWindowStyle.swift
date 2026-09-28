import SwiftUI
import AppKit

/// Applies modal-like chrome to a secondary window (Settings, Activity Log):
/// hides the minimize and zoom buttons, and centers the window over the main
/// Connecter window every time it is (re)opened.
///
/// AppKit shows a window at its remembered position before SwiftUI code gets
/// a chance to move it, which reads as a jump. To avoid that the window is
/// kept fully transparent from the moment it closes (or is created) until it
/// has been positioned on its next show, and only then made visible.
struct ModalWindowStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> StyleView { StyleView() }
    func updateNSView(_ nsView: StyleView, context: Context) {}

    final class StyleView: NSView {
        /// True while the window still has to be repositioned before it is shown.
        private var pendingReposition = true
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true

            // Avoid registering twice if the view moves to a different window.
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []

            let center = NotificationCenter.default

            // Closing: the next show must reposition again; go transparent right
            // away so a reopened window cannot flash at its old place.
            observers.append(center.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.pendingReposition = true
                window.alphaValue = 0
            })

            // Shown (visible or key): layout is done, so the size is final —
            // center now and reveal.
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    guard let self, let window, window.isVisible else { return }
                    self.revealCentered(window)
                })
            }

            // First show: the view is attached before the window is ordered front.
            window.alphaValue = 0
            // Safety net so the window can never stay invisible if no
            // notification arrives (only acts on a window that is on screen).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak window] in
                guard let self, let window, window.isVisible else { return }
                self.revealCentered(window)
            }
        }

        private func revealCentered(_ window: NSWindow) {
            guard pendingReposition else { return }
            pendingReposition = false
            Self.centerWindow(window)
            window.alphaValue = 1
        }

        private static func centerWindow(_ window: NSWindow) {
            let main = NSApp.windows.first {
                $0 !== window
                && $0.isVisible
                && !($0 is NSPanel)
                && $0.level == .normal
                && $0.styleMask.contains(.titled)
            }
            guard let main else {
                window.center()
                return
            }
            var frame = window.frame
            frame.origin.x = main.frame.midX - frame.width / 2
            frame.origin.y = main.frame.midY - frame.height / 2
            // Keep it on the same screen as the main window.
            if let visible = main.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
                frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
                frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
            }
            window.setFrameOrigin(frame.origin)
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}

extension View {
    /// Modal-like chrome, centered presentation and Esc to close.
    func modalWindowStyle() -> some View {
        background(ModalWindowStyle())
            .escapeClosesWindow()
    }
}
