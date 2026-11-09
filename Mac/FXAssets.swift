import Cocoa
import CoreImage

/// 特效贴图：优先用 Mac/FX 里 Codex 生成的 PNG，缺失时用程序画的兜底版本。
/// 黑底贴图会被“抠黑”（亮度变透明度），这样在透明窗口上也能像加法混合一样发光。
enum FXAssets {
    static let spark: CGImage = load("impact_spark", keyBlack: true) ?? glowDot(color: .orange)
    static let smoke: CGImage = load("smoke_puff", keyBlack: true) ?? glowDot(color: NSColor(white: 0.8, alpha: 1))
    static let killBadge: CGImage? = load("kill_badge", keyBlack: true)
    static let bulletHole: CGImage? = load("bullet_hole", keyBlack: false, keyWhite: true)
    static let kfPistol: CGImage? = load("kf_pistol", keyBlack: true, square: false)
    static let kfRifle: CGImage? = load("kf_rifle", keyBlack: true, square: false)
    static let kfHeadshot: CGImage? = load("kf_headshot", keyBlack: true, square: false)
    /// 血滴：深红实心圆 + 一点高光
    static let bloodDrop: CGImage = {
        let s = 40
        let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor(red: 0.62, green: 0.0, blue: 0.03, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 36, height: 36))
        ctx.setFillColor(NSColor(red: 0.9, green: 0.08, blue: 0.1, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: 6, y: 8, width: 26, height: 26))
        ctx.setFillColor(NSColor(white: 1, alpha: 0.45).cgColor)
        ctx.fillEllipse(in: CGRect(x: 22, y: 24, width: 7, height: 7))
        return ctx.makeImage()!
    }()
    static let ember: CGImage = glowDot(color: NSColor(red: 1, green: 0.75, blue: 0.3, alpha: 1))

    private static func load(_ name: String, keyBlack: Bool, keyWhite: Bool = false, square: Bool = true) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let scaled = square ? resize(img, to: 256) : trimmed(img, height: 96)
        if keyBlack { return lumaKey(scaled, invert: false) }
        if keyWhite, img.alphaInfo == .none || img.alphaInfo == .noneSkipLast || img.alphaInfo == .noneSkipFirst {
            return lumaKey(scaled, invert: true)
        }
        return scaled
    }

    private static func resize(_ img: CGImage, to side: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()!
    }

    /// 等比缩放到指定高度，并裁掉四周的纯黑边（击杀栏图标要紧凑）
    private static func trimmed(_ img: CGImage, height: Int) -> CGImage {
        let w = img.width, h = img.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let d = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var minX = w, maxX = 0, minY = h, maxY = 0
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4
            if max(d[i], d[i + 1], d[i + 2]) > 40 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
        } }
        guard maxX > minX, maxY > minY, let cropped = img.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return img }
        let nw = max(1, Int(Double(cropped.width) / Double(cropped.height) * Double(height)))
        let out = CGContext(data: nil, width: nw, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        out.interpolationQuality = .high
        out.draw(cropped, in: CGRect(x: 0, y: 0, width: nw, height: height))
        return out.makeImage()!
    }

    /// invert=false：黑色变透明（发光贴图）；invert=true：白色变透明（白底弹孔）
    private static func lumaKey(_ img: CGImage, invert: Bool) -> CGImage? {
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
            if !invert {
                // 原图 = 颜色 × 亮度（黑底），正好就是预乘 alpha 的形式
                var a = max(r, g, b)
                if a < 10 { a = 0; data[i] = 0; data[i + 1] = 0; data[i + 2] = 0 }
                data[i + 3] = UInt8(a)
            } else {
                let a = 255 - min(r, g, b)
                // 白底合成：c = 颜色·α + 白·(1-α)  ⇒  预乘颜色 = c - 255·(1-α)
                data[i] = UInt8(Double(r - (255 - a)).clamped)
                data[i + 1] = UInt8(Double(g - (255 - a)).clamped)
                data[i + 2] = UInt8(Double(b - (255 - a)).clamped)
                data[i + 3] = UInt8(a)
            }
        }
        return ctx.makeImage()
    }

    static func glowDot(color: NSColor) -> CGImage {
        let s = 64
        let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let c = color.usingColorSpace(.deviceRGB)!
        let colors = [NSColor.white.cgColor, c.cgColor, c.withAlphaComponent(0).cgColor] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.25, 1])!
        ctx.drawRadialGradient(grad, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                               endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        return ctx.makeImage()!
    }

    /// 一条细长的火花（用于粒子）
    static let streak: CGImage = {
        let w = 48, h = 6
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [NSColor(red: 1, green: 0.55, blue: 0.1, alpha: 0).cgColor,
                      NSColor(red: 1, green: 0.8, blue: 0.4, alpha: 1).cgColor,
                      NSColor.white.cgColor] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.7, 1])!
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 1, width: w, height: h - 2), cornerWidth: 2, cornerHeight: 2, transform: nil))
        ctx.clip()
        ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: w, y: 0), options: [])
        return ctx.makeImage()!
    }()
}

private extension Double {
    var clamped: Double { Swift.max(0, Swift.min(255, self)) }
}

extension NSImage {
    private static let ci = CIContext()

    var cg128: CGImage? {
        var r = CGRect(x: 0, y: 0, width: 256, height: 256)
        return cgImage(forProposedRect: &r, context: nil, hints: nil)
    }

    /// 红色剪影（保留明暗）
    func redTinted() -> CGImage? { tinted(NSColor(red: 1, green: 0.06, blue: 0.04, alpha: 0.78)) }
    /// 纯白剪影（命中第一帧闪白）
    func whiteFlash() -> CGImage? { tinted(NSColor(white: 1, alpha: 0.9)) }

    func tinted(_ color: NSColor) -> CGImage? {
        guard let cg = cg128 else { return nil }
        let size = CGSize(width: 256, height: 256)
        guard let ctx = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        ctx.draw(cg, in: rect)
        ctx.setBlendMode(.sourceAtop)
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect)
        return ctx.makeImage()
    }

    /// 阵亡后的灰色版本：去色、压暗、提高对比
    func grayscale() -> CGImage? {
        guard let cg = cg128 else { return nil }
        let img = CIImage(cgImage: cg)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0,
                                                            kCIInputBrightnessKey: -0.08,
                                                            kCIInputContrastKey: 0.9])
        return Self.ci.createCGImage(img, from: img.extent)
    }
}
