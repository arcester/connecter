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
        nsView.applyIfNeeded(animated: true)
    }

    final class ResizingView: NSView {
        var targetSize: NSSize = .zero

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyWindowChrome()
            applyIfNeeded(animated: false)
        }

        private func applyWindowChrome() {
            guard let window else { return }
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.tabbingMode = .disallowed
        }

        func applyIfNeeded(animated: Bool) {
            guard let window = self.window, targetSize != .zero else { return }
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
            window.setFrame(frame, display: true, animate: animated)

            window.minSize = newFrameSize
            window.maxSize = newFrameSize
        }
    }
}
