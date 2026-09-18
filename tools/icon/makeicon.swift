// Genera el icono de la app: carpeta genérica de macOS (del sistema) sobre un NAS con LEDs,
// en fondo azul degradado. Estilo inspirado en Parachute.app.
// Uso:  swift tools/icon/makeicon.swift   → AppIcon-A.png, AppIcon-A-inv.png, AppIcon-A-inv-deep.png y sheet5.png
//       "inv" = degradado más oscuro arriba; "deep" = paleta más profunda. Variante instalada: A-inv-deep.
// Copia la variante elegida a connecter/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

import AppKit
import UniformTypeIdentifiers

let sysFolder = NSWorkspace.shared.icon(for: UTType.folder)

// MARK: - Helpers
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

// MARK: - Elements

func background(deep: Bool = false, darkTop: Bool = false) {
    var colors = deep ? [rgb(52, 124, 222), rgb(14, 56, 150)] : [rgb(78, 156, 245), rgb(24, 84, 190)]
    if darkTop { colors.reverse() }
    NSGradient(colors: colors)!.draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -90)
    // soft highlight on the lighter side
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(rect: NSRect(x: 0, y: 0, width: S, height: S)),
              relativeCenterPosition: NSPoint(x: -0.5, y: darkTop ? -0.65 : 0.65))
}

/// Genuine macOS folder icon drawn into a square rect (the artwork keeps its own proportions)
func systemFolder(_ ctx: CGContext, x: CGFloat, y: CGFloat, size: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: NSColor.black.withAlphaComponent(0.30).cgColor)
    sysFolder.draw(in: NSRect(x: x, y: y, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    ctx.restoreGState()
}

/// Dark NAS/server unit with drive bays and green LEDs
func server(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, bays: Int = 3) {
    let r: CGFloat = w * 0.09
    let body = rr(NSRect(x: x, y: y, width: w, height: h), r)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    rgb(52, 62, 76).setFill(); body.fill()
    ctx.restoreGState()
    NSGradient(colors: [rgb(96, 108, 124), rgb(44, 52, 64)])!.draw(in: body, angle: -90)
    // top edge highlight
    ctx.saveGState(); body.addClip()
    NSColor.white.withAlphaComponent(0.22).setFill(); NSRect(x: x, y: y + h - 8, width: w, height: 8).fill()
    ctx.restoreGState()
    // bays
    let inset = w * 0.09
    let gap = h * 0.06
    let bayH = (h - inset * 2 - gap * CGFloat(bays - 1)) / CGFloat(bays)
    for i in 0..<bays {
        let by = y + inset + CGFloat(i) * (bayH + gap)
        let bay = rr(NSRect(x: x + inset, y: by, width: w - inset * 2, height: bayH), bayH * 0.28)
        NSGradient(colors: [rgb(26, 32, 42), rgb(38, 45, 57)])!.draw(in: bay, angle: -90)
        // subtle grille lines
        rgb(60, 70, 84).setFill()
        var gx = x + inset + bayH * 0.5
        while gx < x + w - inset - bayH * 1.2 {
            NSRect(x: gx, y: by + bayH * 0.32, width: 4, height: bayH * 0.36).fill(); gx += bayH * 0.32
        }
        // LED
        let led = NSPoint(x: x + w - inset - bayH * 0.55, y: by + bayH / 2)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: bayH * 0.45, color: rgb(52, 199, 89).cgColor)
        rgb(76, 217, 100).setFill()
        NSBezierPath(ovalIn: NSRect(x: led.x - bayH * 0.17, y: led.y - bayH * 0.17, width: bayH * 0.34, height: bayH * 0.34)).fill()
        ctx.restoreGState()
    }
}

func dots(_ ctx: CGContext, x: CGFloat, from y0: CGFloat, to y1: CGFloat, count: Int = 3, radius: CGFloat = 15) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    NSColor.white.withAlphaComponent(0.95).setFill()
    for i in 0..<count {
        let t = CGFloat(i + 1) / CGFloat(count + 1)
        let y = y0 + (y1 - y0) * t
        NSBezierPath(ovalIn: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
    }
    ctx.restoreGState()
}

func waves(_ ctx: CGContext, center: NSPoint, radii: [CGFloat], width: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: NSColor.black.withAlphaComponent(0.2).cgColor)
    NSColor.white.withAlphaComponent(0.92).setStroke()
    for rad in radii {
        let a = NSBezierPath(); a.appendArc(withCenter: center, radius: rad, startAngle: 38, endAngle: 142)
        a.lineWidth = width; a.lineCapStyle = .round; a.stroke()
    }
    ctx.restoreGState()
}

// MARK: - Variants

func render(_ variant: String) -> NSBitmapImageRep {
    let rep = bitmap(Int(S), Int(S))
    draw(into: rep) { ctx in
        background(deep: variant.contains("deep"), darkTop: variant.contains("inv"))
        switch variant {
        case "A", "A-inv", "A-inv-deep":  // macOS folder above, dots, server below
            server(ctx, x: 302, y: 150, w: 420, h: 240)
            dots(ctx, x: 512, from: 390, to: 575, radius: 17)
            systemFolder(ctx, x: 252, y: 462, size: 520)
        default:   // "B" / "B-deep": server emitting waves toward the macOS folder
            server(ctx, x: 302, y: 130, w: 420, h: 230)
            waves(ctx, center: NSPoint(x: 512, y: 368), radii: [60, 114, 168], width: 28)
            systemFolder(ctx, x: 252, y: 470, size: 520)
        }
    }
    savePNG(rep, "AppIcon-\(variant).png")
    return rep
}

let variants = ["A", "A-inv", "A-inv-deep"]
let reps = variants.map(render)

// MARK: - Sheet
func masked(_ src: NSBitmapImageRep, size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let r = size * 0.2237
    rr(NSRect(x: 0, y: 0, width: size, height: size), r).addClip()
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
        }
        NSAttributedString(string: variants[i], attributes: [.font: NSFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: rgb(60, 60, 67)])
            .draw(at: NSPoint(x: x + 70, y: 400 + 40))
        NSAttributedString(string: variants[i], attributes: [.font: NSFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: rgb(200, 200, 205)])
            .draw(at: NSPoint(x: x + 70, y: 40))
    }
}
savePNG(sheet, "sheet5.png")
print("ok")
