// Genera el icono de la app: carpeta plana blanca→azul (degradado) con sombra suave
// y una cola de puntos (con su propia sombra), sobre fondo azul casi plano calcado
// del icono de referencia (estilo PayPal).
// Uso:  swift tools/icon/makeicon.swift   → AppIcon-shadow-1/2/3.png y sheet9.png
// Variante instalada: shadow-2 (carpeta + puntos verticales debajo, con sombra).

import AppKit

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
func rr(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }

let S: CGFloat = 1024
// Colors sampled from the reference icon (PayPal-style "P")
let bgTop = rgb(3, 163, 255), bgBottom = rgb(0, 148, 242)      // near-flat vivid blue
let bg = NSGradient(colors: [bgTop, bgBottom])!
func bgColor(atY y: CGFloat) -> NSColor { bg.interpolatedColor(atLocation: 1 - y / S) }

let glyphTop = NSColor.white, glyphBottom = rgb(171, 219, 255) // white fading to soft blue
let glyphGradient = NSGradient(colors: [glyphTop, glyphBottom])!

/// Flat folder silhouette: body + tab with a small slanted join (like SF Symbols' folder.fill)
func folderPath(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> NSBezierPath {
    let r: CGFloat = w * 0.09
    let tabW = w * 0.40, tabH = h * 0.17
    let p = rr(NSRect(x: x, y: y, width: w, height: h - tabH), r)
    // tab: rounded top corners, joined to the body
    let tab = NSBezierPath()
    let tx0 = x, tx1 = x + tabW, ty0 = y + h - tabH - r, ty1 = y + h
    tab.move(to: NSPoint(x: tx0, y: ty0))
    tab.line(to: NSPoint(x: tx0, y: ty1 - r))
    tab.appendArc(withCenter: NSPoint(x: tx0 + r, y: ty1 - r), radius: r, startAngle: 180, endAngle: 90, clockwise: true)
    tab.line(to: NSPoint(x: tx1 - r * 0.9, y: ty1))
    tab.appendArc(withCenter: NSPoint(x: tx1 - r * 0.9, y: ty1 - r * 0.9), radius: r * 0.9, startAngle: 90, endAngle: 20, clockwise: true)
    tab.line(to: NSPoint(x: tx1 + tabH * 0.9, y: ty0))
    tab.close()
    p.append(tab)
    p.windingRule = .nonZero
    return p
}

func render(_ variant: String) -> NSBitmapImageRep {
    let rep = bitmap(Int(S), Int(S))
    draw(into: rep) { ctx in
        bg.draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -90)
        func fillGlyph(_ path: NSBezierPath, in rect: NSRect) {
            // Cast a soft shadow first (opaque fill so the shadow reads clearly),
            // then paint the gradient on top of the now-shadowed shape.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 32, color: NSColor.black.withAlphaComponent(0.34).cgColor)
            NSColor.white.setFill()
            path.fill()
            ctx.restoreGState()

            ctx.saveGState()
            path.addClip()
            glyphGradient.draw(in: rect, angle: -90)
            ctx.restoreGState()
        }
        func fillDot(_ path: NSBezierPath, color: NSColor) {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 14, color: NSColor.black.withAlphaComponent(0.35).cgColor)
            color.setFill()
            path.fill()
            ctx.restoreGState()
        }
        switch variant {
        case "1":  // big folder, three dots punched into the body
            let fx: CGFloat = 172, fy: CGFloat = 262, fw: CGFloat = 680, fh: CGFloat = 500
            let folder1 = folderPath(x: fx, y: fy, w: fw, h: fh)
            fillGlyph(folder1, in: NSRect(x: fx, y: fy, width: fw, height: fh))
            let cy = fy + (fh - fh * 0.17) * 0.47, rad: CGFloat = 40, gap: CGFloat = 150
            for i in -1...1 {
                let cx = fx + fw / 2 + CGFloat(i) * gap
                bgColor(atY: cy).setFill()
                NSBezierPath(ovalIn: NSRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2)).fill()
            }
        case "2":  // folder above, vertical dot trail below
            let fx: CGFloat = 212, fy: CGFloat = 430, fw: CGFloat = 600, fh: CGFloat = 440
            let folder2 = folderPath(x: fx, y: fy, w: fw, h: fh)
            fillGlyph(folder2, in: NSRect(x: fx, y: fy, width: fw, height: fh))
            for (i, y) in [340.0, 250.0, 160.0].enumerated() {
                let rad: CGFloat = 30 - CGFloat(i) * 4
                fillDot(NSBezierPath(ovalIn: NSRect(x: 512 - rad, y: CGFloat(y) - rad, width: rad * 2, height: rad * 2)), color: glyphTop)
            }
        default:   // "3": folder above, three dots in a row below
            let fx: CGFloat = 212, fy: CGFloat = 400, fw: CGFloat = 600, fh: CGFloat = 440
            let folder3 = folderPath(x: fx, y: fy, w: fw, h: fh)
            fillGlyph(folder3, in: NSRect(x: fx, y: fy, width: fw, height: fh))
            let rad: CGFloat = 34, gap: CGFloat = 130, cy: CGFloat = 262
            for i in -1...1 {
                let cx = 512 + CGFloat(i) * gap
                fillDot(NSBezierPath(ovalIn: NSRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2)), color: glyphTop)
            }
        }
    }
    savePNG(rep, "AppIcon-shadow2-\(variant).png")
    return rep
}

let variants = ["1", "2", "3"]
let reps = variants.map(render)

func masked(_ src: NSBitmapImageRep, size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    rr(NSRect(x: 0, y: 0, width: size, height: size), size * 0.2237).addClip()
    NSImage(cgImage: src.cgImage!, size: NSSize(width: size, height: size)).draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    img.unlockFocus()
    return img
}
let sheet = bitmap(1200, 800)
draw(into: sheet) { _ in
    rgb(242, 242, 247).setFill(); NSRect(x: 0, y: 400, width: 1200, height: 400).fill()
    rgb(28, 28, 30).setFill();    NSRect(x: 0, y: 0,   width: 1200, height: 400).fill()
    for (i, rep) in reps.enumerated() {
        let x = CGFloat(i) * 400
        for y0 in [400.0, 0.0] as [CGFloat] {
            masked(rep, size: 260).draw(in: NSRect(x: x + 70, y: y0 + 120, width: 260, height: 260))
            var cx = x + 190
            for s in [64.0, 32.0, 16.0] as [CGFloat] {
                masked(rep, size: s).draw(in: NSRect(x: cx, y: y0 + 30 + (64 - s)/2, width: s, height: s)); cx += s + 30
            }
            NSAttributedString(string: variants[i], attributes: [.font: NSFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: y0 > 0 ? rgb(60, 60, 67) : rgb(200, 200, 205)])
                .draw(at: NSPoint(x: x + 70, y: y0 + 40))
        }
    }
}
savePNG(sheet, "sheet9.png")
print("ok")
