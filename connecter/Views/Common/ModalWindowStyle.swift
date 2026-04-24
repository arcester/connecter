import SwiftUI
import AppKit

/// Applies modal-like chrome to a secondary window:
/// hides minimize and zoom buttons, and centers over the main Connecter window
/// every time the window is freshly opened (not on every focus change).
struct ModalWindowStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> StyleView { StyleView() }
    func updateNSView(_ nsView: StyleView, context: Context) {}

    final class StyleView: NSView {
        // Set to true when the window closes so the next show re-centers.
        private var shouldCenterOnNextShow = true
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true

            // Avoid registering twice if view moves to a different window.
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []

            // When window closes, mark that the next show should re-center.
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                self?.shouldCenterOnNextShow = true
            })

            // When window becomes key, center if it was just (re)opened.
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window, queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window, self.shouldCenterOnNextShow else { return }
                self.shouldCenterOnNextShow = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    Self.centerWindow(window)
                }
            })

            // First show.
            if shouldCenterOnNextShow {
                shouldCenterOnNextShow = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak window] in
                    guard let window else { return }
                    Self.centerWindow(window)
                }
            }
        }

        private static func centerWindow(_ window: NSWindow) {
            let main = NSApp.windows.first {
                $0 !== window
                && $0.isVisible
                && !($0 is NSPanel)
                && $0.level == .normal
                && $0.styleMask.contains(.titled)
            }
            var f = window.frame
            if let main {
                f.origin.x = main.frame.midX - f.width / 2
                f.origin.y = main.frame.midY - f.height / 2
            } else {
                window.center(); return
            }
            window.setFrameOrigin(f.origin)
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}

extension View {
    func modalWindowStyle() -> some View {
        background(ModalWindowStyle())
    }
}
