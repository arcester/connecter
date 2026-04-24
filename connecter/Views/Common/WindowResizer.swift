import SwiftUI
import AppKit

/// Drives the host NSWindow's content size from SwiftUI and applies window chrome tweaks.
/// Place as `.background(WindowResizer(width:height:))` on the root view.
struct WindowResizer: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> ResizingView {
        let view = ResizingView()
        view.targetSize = NSSize(width: width, height: height)
        return view
    }

    func updateNSView(_ nsView: ResizingView, context: Context) {
        nsView.targetSize = NSSize(width: width, height: height)
        // Defer so the resize doesn't happen mid-layout, which causes reentrancy warnings.
        DispatchQueue.main.async { nsView.applyIfNeeded(animated: true) }
    }

    final class ResizingView: NSView {
        var targetSize: NSSize = .zero
        // True once the content-measured size has been applied at least once.
        private var settled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Hide until the real measured size arrives so the user never sees
            // the fallback-height window flash before it snaps to the right size.
            settled = false
            window.alphaValue = 0
            applyWindowChrome()
        }

        private func applyWindowChrome() {
            guard let window else { return }
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.tabbingMode = .disallowed
        }

        func applyIfNeeded(animated: Bool) {
            guard let window = self.window, targetSize != .zero else { return }

            // Always reveal the window once we have the target size, even if no
            // resize is needed (sizes already match).
            defer {
                if !settled {
                    settled = true
                    window.alphaValue = 1
                }
            }

            let currentContent = window.contentRect(forFrameRect: window.frame).size
            let dw = abs(currentContent.width - targetSize.width)
            let dh = abs(currentContent.height - targetSize.height)
            if dw < 0.5 && dh < 0.5 { return }

            let hadResizable = window.styleMask.contains(.resizable)
            if !hadResizable { window.styleMask.insert(.resizable) }

            let newFrameSize = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: targetSize)
            ).size
            var frame = window.frame
            let topY = frame.maxY
            frame.size = newFrameSize
            frame.origin.y = topY - newFrameSize.height
            // Only animate after the initial sizing is done.
            window.setFrame(frame, display: true, animate: animated && settled)

            window.minSize = newFrameSize
            window.maxSize = newFrameSize
        }
    }
}
