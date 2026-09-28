import SwiftUI
import AppKit

/// Closes the host window when Esc is pressed while it is the key window and
/// has no sheet attached (a sheet's own Cancel keeps handling Esc). Modifier
/// keys must be up, so shortcuts such as ⌥⎋ are left alone.
struct EscapeClosesWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ nsView: MonitorView, context: Context) {}

    final class MonitorView: NSView {
        private static let escapeKeyCode: UInt16 = 53
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let window = self?.window,
                      event.keyCode == Self.escapeKeyCode,
                      event.window === window,
                      window.attachedSheet == nil,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
                else { return event }
                window.performClose(nil)
                return nil
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

extension View {
    /// Lets Esc close the window this view lives in.
    func escapeClosesWindow() -> some View {
        background(EscapeClosesWindow())
    }
}
