// Genera el icono de la app a partir de la carpeta genérica de macOS + glifo de señal.
// Uso:  swift tools/icon/makeicon.swift            → AppIcon-orange.png, -white.png, -green.png y variants-sheet.png
//       GX/GY (centro del glifo), GS (escala), FI (margen de la carpeta) ajustables por variable de entorno.
// Copia la variante elegida a connecter/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

import AppKit
import UniformTypeIdentifiers

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}
func savePNG(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func draw(into rep: NSBitmapImageRep, _ body: (CGContext) -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    gc.imageInterpolation = .high
    body(gc.cgContext)
    gc.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
}

// The genuine macOS folder icon, from the system
let folder = NSWorkspace.shared.icon(for: UTType.folder)
let best = folder.representations.max { $0.pixelsWide < $1.pixelsWide }!
print("system folder icon: best rep \(best.pixelsWide)px")

let S: CGFloat = 1024
// Glyph geometry: tweak via env for iteration
let env = ProcessInfo.processInfo.environment
let gx = CGFloat(Double(env["GX"] ?? "400")!)
let gy = CGFloat(Double(env["GY"] ?? "300")!)
let gs = CGFloat(Double(env["GS"] ?? "1.0")!)   // glyph scale
let folderInset = CGFloat(Double(env["FI"] ?? "60")!)

func render(glyph: NSColor, name: String) -> NSBitmapImageRep {
    let rep = bitmap(Int(S), Int(S))
    draw(into: rep) { ctx in
        // Light neutral background so the blue folder stands out
        NSGradient(colors: [rgb(252, 252, 254), rgb(226, 231, 240)])!
            .draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -90)

        // System folder, centered
        let fr = NSRect(x: folderInset, y: folderInset, width: S - 2*folderInset, height: S - 2*folderInset)
        folder.draw(in: fr, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])

        // Signal glyph: dot + three arcs, with a soft shadow for contrast on the folder
        let c = NSPoint(x: gx, y: gy)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6*gs), blur: 18*gs, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        glyph.setFill(); glyph.setStroke()
        let dr = 40*gs
        NSBezierPath(ovalIn: NSRect(x: c.x - dr, y: c.y - dr, width: 2*dr, height: 2*dr)).fill()
        for radius in [108.0, 186.0, 264.0] as [CGFloat] {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: radius*gs, startAngle: 6, endAngle: 84)
            arc.lineWidth = 46*gs
            arc.lineCapStyle = .round
            arc.stroke()
        }
        ctx.restoreGState()
    }
    savePNG(rep, "AppIcon-\(name).png")
    return rep
}

let variants: [(String, NSColor)] = [
    ("orange", rgb(255, 159, 10)),   // system orange
    ("white",  NSColor.white),
    ("green",  rgb(52, 199, 89)),    // system green
]
let reps = variants.map { render(glyph: $0.1, name: $0.0) }

// Preview sheet: three variants masked, light + dark, with small sizes
func masked(_ src: NSBitmapImageRep, size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let r = size * 0.2237
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: r, yRadius: r).addClip()
    NSImage(cgImage: src.cgImage!, size: NSSize(width: size, height: size)).draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    img.unlockFocus()
    return img
}
let sheet = bitmap(1200, 760)
draw(into: sheet) { _ in
    rgb(242, 242, 247).setFill(); NSRect(x: 0, y: 380, width: 1200, height: 380).fill()
    rgb(28, 28, 30).setFill();    NSRect(x: 0, y: 0,   width: 1200, height: 380).fill()
    for (i, rep) in reps.enumerated() {
        let x = CGFloat(i) * 400
        for y0 in [380.0, 0.0] as [CGFloat] {
            masked(rep, size: 260).draw(in: NSRect(x: x + 70, y: y0 + 100, width: 260, height: 260))
            var cx = x + 40
            for s in [64.0, 32.0, 16.0] as [CGFloat] {
                masked(rep, size: s).draw(in: NSRect(x: cx, y: y0 + 20 + (64 - s)/2, width: s, height: s)); cx += s + 30
            }
        }
        let label = NSAttributedString(string: variants[i].0, attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: rgb(60, 60, 67)])
        label.draw(at: NSPoint(x: x + 70, y: 380 + 40))
    }
}
savePNG(sheet, "variants-sheet.png")
print("ok")
