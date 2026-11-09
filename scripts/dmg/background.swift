import Cocoa
// 安装窗口背景：640x400 点，左边 PhoneGun 图标(160,200)，右边「应用程序」(480,200)
func render(scale: CGFloat, to outPath: String) {
    let W: CGFloat = 640, H: CGFloat = 400
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // 背景：和图标呼应的淡紫渐变
    NSGradient(colors: [NSColor(red: 0.96, green: 0.95, blue: 1.0, alpha: 1),
                        NSColor(red: 0.89, green: 0.87, blue: 1.0, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
    // 标题
    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: color, .paragraphStyle: p]
        NSAttributedString(string: s, attributes: a).draw(in: NSRect(x: 0, y: y, width: W, height: size * 1.5))
    }
    let ink = NSColor(red: 0.27, green: 0.22, blue: 0.55, alpha: 1)
    text("把 PhoneGun 拖进「应用程序」", size: 26, weight: .heavy, color: ink, y: H - 72)
    text("然后从「应用程序」里打开它，点菜单栏的 ⌖ 扫码开打", size: 14, weight: .medium,
         color: ink.withAlphaComponent(0.7), y: 92)
    // 箭头：从左图标指向右边文件夹（Finder 里 y 向下，这里 y 向上，图标中心在 y=200）
    let c = NSColor(red: 1.0, green: 0.42, blue: 0.55, alpha: 1)
    c.setStroke(); c.setFill()
    let cy: CGFloat = H - 200
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 252, y: cy + 4))
    path.curve(to: NSPoint(x: 376, y: cy + 4), controlPoint1: NSPoint(x: 290, y: cy + 34), controlPoint2: NSPoint(x: 338, y: cy + 34))
    path.lineWidth = 7; path.lineCapStyle = .round
    let dash: [CGFloat] = [0.1, 15]; path.setLineDash(dash, count: 2, phase: 0)
    path.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 392, y: cy - 4))
    head.line(to: NSPoint(x: 366, y: cy + 18))
    head.line(to: NSPoint(x: 362, y: cy - 10))
    head.close()
    head.lineJoinStyle = .round; head.lineWidth = 4
    head.fill(); head.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
}
render(scale: 1, to: CommandLine.arguments[1])
render(scale: 2, to: CommandLine.arguments[2])
