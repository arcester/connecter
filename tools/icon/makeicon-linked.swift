// Icon concept "carpeta enlazada": a light folder on a deep blue → cyan gradient,
// with a link glyph that reads as "connected". Three variants:
//   A  badge   — circular badge at the bottom-right with a two-ring link glyph
//   B  cutout  — large link glyph cut out of the folder body (shows the background)
//   C  nodes   — three dots joined by a line under the folder (evolves the current dots)
// Usage:  swift tools/icon/makeicon-linked.swift <outputDir>
//         → <outputDir>/AppIcon-A.png, -B.png, -C.png (1024 px) and sheet.png

import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

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
// Background: deep blue (top-left) → cyan (bottom-right); away from Finder blue and AutoMounter red.
let bgA = rgb(10, 71, 255), bgB = rgb(23, 198, 242)
let bg = NSGradient(colors: [bgA, bgB])!
let glyphTop = NSColor.white, glyphBottom = rgb(214, 236, 255)
let glyphGradient = NSGradient(colors: [glyphTop, glyphBottom])!
let inkBlue = rgb(8, 52, 190)   // for glyphs drawn on white

/// Flat folder silhouette: body + tab with a slanted join.
func folderPath(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> NSBezierPath {
    let r: CGFloat = w * 0.09
    let tabW = w * 0.40, tabH = h * 0.17
    let p = rr(NSRect(x: x, y: y, width: w, height: h - tabH), r)
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

/// Chain-link glyph (two overlapping rounded rings, 45° tilt) as a stroked path.
func linkPath(center: NSPoint, size: CGFloat) -> NSBezierPath {
    let w = size * 0.62, h = size * 0.34, r = h / 2
    let offset = size * 0.21
    let path = NSBezierPath()
    for sign in [-1.0, 1.0] as [CGFloat] {
        let rect = NSRect(x: center.x - w / 2 + sign * offset, y: center.y - h / 2 + sign * offset * 0.0, width: w, height: h)
        let ring = rr(rect, r)
        // rotate 45° around the glyph centre
        var t = AffineTransform(translationByX: center.x, byY: center.y)
        t.rotate(byDegrees: -45)
        t.translate(x: -center.x, y: -center.y)
        ring.transform(using: t)
        path.append(ring)
    }
    return path
}

func fillGlyph(_ ctx: CGContext, _ path: NSBezierPath, in rect: NSRect) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.30).cgColor)
    NSColor.white.setFill()
    path.fill()
    ctx.restoreGState()
    ctx.saveGState()
    path.addClip()
    glyphGradient.draw(in: rect, angle: -90)
    ctx.restoreGState()
}

func render(_ variant: String) -> NSBitmapImageRep {
    let rep = bitmap(Int(S), Int(S))
    draw(into: rep) { ctx in
        bg.draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -55)

        switch variant {
        case "A":  // folder + circular link badge at the bottom-right
            let fx: CGFloat = 176, fy: CGFloat = 290, fw: CGFloat = 672, fh: CGFloat = 470
            fillGlyph(ctx, folderPath(x: fx, y: fy, w: fw, h: fh), in: NSRect(x: fx, y: fy, width: fw, height: fh))
            let bc = NSPoint(x: fx + fw - 40, y: fy + 30), br: CGFloat = 150
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.30).cgColor)
            inkBlue.setFill()
            NSBezierPath(ovalIn: NSRect(x: bc.x - br, y: bc.y - br, width: br * 2, height: br * 2)).fill()
            ctx.restoreGState()
            // white ring around the badge so it separates from the folder
            NSColor.white.setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: bc.x - br, y: bc.y - br, width: br * 2, height: br * 2))
            ring.lineWidth = 22; ring.stroke()
            let link = linkPath(center: bc, size: 200)
            link.lineWidth = 30; link.lineCapStyle = .round; link.lineJoinStyle = .round
            NSColor.white.setStroke(); link.stroke()

        case "B":  // large link glyph cut out of the folder body
            let fx: CGFloat = 176, fy: CGFloat = 262, fw: CGFloat = 672, fh: CGFloat = 500
            let folder = folderPath(x: fx, y: fy, w: fw, h: fh)
            let link = linkPath(center: NSPoint(x: fx + fw / 2, y: fy + (fh - fh * 0.17) * 0.47), size: 380)
            link.lineWidth = 58; link.lineCapStyle = .round; link.lineJoinStyle = .round
            // punch the stroked link out of the folder: draw folder, then erase with the link stroke
            fillGlyph(ctx, folder, in: NSRect(x: fx, y: fy, width: fw, height: fh))
            ctx.saveGState()
            ctx.setBlendMode(.destinationOut)
            NSColor.black.setStroke(); link.stroke()
            ctx.restoreGState()
            // repaint background through the hole (destinationOut cleared to transparent)
            ctx.saveGState()
            ctx.setBlendMode(.destinationOver)
            bg.draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -55)
            ctx.restoreGState()

        default:   // "C": folder + three nodes joined by a line
            let fx: CGFloat = 212, fy: CGFloat = 400, fw: CGFloat = 600, fh: CGFloat = 440
            fillGlyph(ctx, folderPath(x: fx, y: fy, w: fw, h: fh), in: NSRect(x: fx, y: fy, width: fw, height: fh))
            let cy: CGFloat = 262, gap: CGFloat = 150, rad: CGFloat = 36
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: NSColor.black.withAlphaComponent(0.30).cgColor)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 512 - gap, y: cy)); line.line(to: NSPoint(x: 512 + gap, y: cy))
            line.lineWidth = 22; line.lineCapStyle = .round
            NSColor.white.setStroke(); line.stroke()
            for i in -1...1 {
                let cx = 512 + CGFloat(i) * gap
                NSColor.white.setFill()
                NSBezierPath(ovalIn: NSRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2)).fill()
            }
            ctx.restoreGState()
        }
    }
    savePNG(rep, "\(outDir)/AppIcon-\(variant).png")
    return rep
}

let variants = ["A", "B", "C"]
let reps = variants.map(render)

func masked(_ src: NSBitmapImageRep, size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    rr(NSRect(x: 0, y: 0, width: size, height: size), size * 0.2237).addClip()
    NSImage(cgImage: src.cgImage!, size: NSSize(width: size, height: size)).draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    img.unlockFocus()
    return img
}
// Contact sheet: each variant at 256 / 64 / 32 / 16 on light and dark, plus the current icon for reference.
let current = NSImage(contentsOfFile: "/Users/guzman/Desarrollo/Xcode/connecter/connecter/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png")
let cols = variants.count + 1, colW: CGFloat = 330
let sheet = bitmap(Int(colW) * cols, 800)
draw(into: sheet) { _ in
    rgb(242, 242, 247).setFill(); NSRect(x: 0, y: 400, width: colW * CGFloat(cols), height: 400).fill()
    rgb(28, 28, 30).setFill();    NSRect(x: 0, y: 0,   width: colW * CGFloat(cols), height: 400).fill()
    for col in 0..<cols {
        let x = CGFloat(col) * colW
        let img: NSImage
        let title: String
        if col == 0 {
            title = "Actual"
            let big = NSImage(size: NSSize(width: 1024, height: 1024)); big.lockFocus(); current?.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024)); big.unlockFocus(); img = big
        } else {
            title = "Variante \(variants[col - 1])"
            img = NSImage(cgImage: reps[col - 1].cgImage!, size: NSSize(width: 1024, height: 1024))
        }
        func maskedImg(_ size: CGFloat) -> NSImage {
            let m = NSImage(size: NSSize(width: size, height: size)); m.lockFocus()
            rr(NSRect(x: 0, y: 0, width: size, height: size), size * 0.2237).addClip()
            img.draw(in: NSRect(x: 0, y: 0, width: size, height: size)); m.unlockFocus(); return m
        }
        for y0 in [400.0, 0.0] as [CGFloat] {
            maskedImg(220).draw(in: NSRect(x: x + 40, y: y0 + 140, width: 220, height: 220))
            var cx = x + 40
            for s in [64.0, 32.0, 16.0] as [CGFloat] {
                maskedImg(s).draw(in: NSRect(x: cx, y: y0 + 60 + (64 - s) / 2, width: s, height: s)); cx += s + 28
            }
            NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: y0 > 0 ? rgb(60, 60, 67) : rgb(200, 200, 205)])
                .draw(at: NSPoint(x: x + 40, y: y0 + 18))
        }
    }
}
savePNG(sheet, "\(outDir)/sheet.png")
print("ok")
