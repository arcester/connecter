import SwiftUI
import AppKit

/// Animates the host NSWindow's content size and applies window chrome tweaks.
/// Window sizing is driven from SwiftUI via `width`/`height`; the actual frame
/// transition uses `NSWindow.setFrame(_:display:animate:)` for a smooth resize.
struct WindowResizer: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> ResizingView {
        let view = ResizingView()
        view.targetSize = NSSize(width: width, height: height)
        return view
    }

    func updateNSView(_ nsView: ResizingView, context: Context) {
        let newSize = NSSize(width: width, height: height)
        // Only apply when the target actually changes — prevents redundant work
        // when SwiftUI re-renders for unrelated reasons.
        guard nsView.targetSize != newSize else { return }
        nsView.targetSize = newSize
        DispatchQueue.main.async { nsView.applyIfNeeded(animated: true) }
    }

    final class ResizingView: NSView {
        var targetSize: NSSize = .zero
        private var settled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            settled = false
            window.alphaValue = 0
            applyWindowChrome()
            // Apply the initial size without animation so the window doesn't
            // fade in at the wrong size.
            DispatchQueue.main.async { self.applyIfNeeded(animated: false) }
        }

        private func applyWindowChrome() {
            guard let window else { return }
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.tabbingMode = .disallowed
        }

        func applyIfNeeded(animated: Bool) {
            guard let window = self.window, targetSize != .zero else { return }

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

            let newFrameSize = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: targetSize)
            ).size
            var frame = window.frame
            let topY = frame.maxY
            frame.size = newFrameSize
            frame.origin.y = topY - newFrameSize.height

            guard animated && settled else {
                window.setFrame(frame, display: true)
                return
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        }
    }
}
