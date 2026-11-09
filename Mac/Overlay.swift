import Cocoa
import QuartzCore

/// 每块屏幕一个全透明、鼠标穿透、置顶的窗口；所有特效都用 CALayer 画（由系统渲染服务器按屏幕刷新率跑，ProMotion 下 120Hz）。
/// 对外统一用辅助功能坐标（主屏左上角为原点，y 向下）。
final class Overlay {
    private var windows: [(screen: NSScreen, window: NSWindow, root: CALayer)] = []
    private let crosshair = CrosshairLayer()
    private var crosshairHost: CALayer?
    private var hpBars: [String: HPBarLayer] = [:]
    private var hpPinned: Set<String> = []
    private var hpHideWork: [String: DispatchWorkItem] = [:]
    private var deadLayers: [String: CALayer] = [:]
    private var feed: [CALayer] = []
    private var vignette: CAGradientLayer?

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    // 缓动曲线
    static let easeOutCubic = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)
    static let easeOutBack = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
    static let easeInOutCubic = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
    static let easeInQuad = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0)

    init() {
        crosshair.zPosition = 10_000   // 准星永远在所有特效、阵亡图标、血条之上
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
    }

    func rebuild() {
        windows.forEach { $0.window.orderOut(nil) }
        windows.removeAll()
        hpBars.removeAll(); deadLayers.removeAll(); feed.removeAll(); vignette = nil
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            v.wantsLayer = true
            let root = CALayer()
            root.frame = v.bounds
            v.layer = root
            w.contentView = v
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append((screen, w, root))
        }
        crosshairHost = nil
    }

    var bounds: CGRect {
        windows.map { axRect(fromCocoa: $0.screen.frame) }.reduce(CGRect.null) { $0.union($1) }
    }

    var mainScreenRect: CGRect { axRect(fromCocoa: NSScreen.screens.first?.frame ?? .zero) }

    // MARK: - coordinates

    private func axRect(fromCocoa r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    private func host(for p: CGPoint) -> (CALayer, CGPoint)? {
        let cocoa = CGPoint(x: p.x, y: primaryHeight - p.y)
        guard let w = windows.first(where: { $0.screen.frame.contains(cocoa) }) ?? windows.first else { return nil }
        return (w.root, CGPoint(x: cocoa.x - w.screen.frame.minX, y: cocoa.y - w.screen.frame.minY))
    }

    private func host(for r: CGRect) -> (CALayer, CGRect)? {
        guard let (layer, c) = host(for: CGPoint(x: r.midX, y: r.midY)) else { return nil }
        return (layer, CGRect(x: c.x - r.width / 2, y: c.y - r.height / 2, width: r.width, height: r.height))
    }

    private var mainRoot: CALayer? { windows.first?.root }

    // MARK: - crosshair

    func moveCrosshair(to p: CGPoint, onTarget: Bool) {
        guard let (root, lp) = host(for: p) else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if crosshairHost !== root {
            crosshair.removeFromSuperlayer()
            root.addSublayer(crosshair)
            crosshairHost = root
        }
        crosshair.position = lp
        crosshair.setHot(onTarget)
        CATransaction.commit()
    }

    func recoil() { crosshair.kick() }

    // MARK: - impacts

    /// 子弹打在图标上：闪光贴图 + 火花粒子
    func impact(at p: CGPoint, scale: CGFloat = 1) {
        guard let (root, lp) = host(for: p) else { return }
        let flash = CALayer()
        flash.contents = FXAssets.spark
        let s = 120 * scale
        flash.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        flash.position = lp
        flash.transform = CATransform3DMakeRotation(.random(in: 0...(2 * .pi)), 0, 0, 1)
        root.addSublayer(flash)
        let sc = CAKeyframeAnimation(keyPath: "transform.scale"); sc.values = [0.25, 1.0, 1.15]; sc.keyTimes = [0, 0.3, 1]
        let op = CAKeyframeAnimation(keyPath: "opacity"); op.values = [1, 1, 0]; op.keyTimes = [0, 0.35, 1]
        run([sc, op], on: flash, duration: 0.16, timing: Self.easeOutCubic)
        burst(at: lp, in: root, count: 18, speed: 420, color: nil)
    }

    /// 打空：弹孔贴花 + 灰尘
    func miss(at p: CGPoint) {
        guard let (root, lp) = host(for: p) else { return }
        let hole = CALayer()
        if let img = FXAssets.bulletHole {
            hole.contents = img
            hole.bounds = CGRect(x: 0, y: 0, width: 46, height: 46)
        } else {
            hole.bounds = CGRect(x: 0, y: 0, width: 9, height: 9)
            hole.cornerRadius = 4.5
            hole.backgroundColor = NSColor(white: 0.05, alpha: 0.9).cgColor
            hole.borderColor = NSColor(white: 0.9, alpha: 0.5).cgColor
            hole.borderWidth = 1.5
        }
        hole.position = lp
        hole.transform = CATransform3DMakeRotation(.random(in: 0...(2 * .pi)), 0, 0, 1)
        root.addSublayer(hole)
        let pop = CAKeyframeAnimation(keyPath: "transform.scale"); pop.values = [1.4, 1]; pop.duration = 0.08
        hole.add(pop, forKey: nil)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + 3; fade.duration = 1.2
        fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
        hole.add(fade, forKey: nil)
        after(4.3) { hole.removeFromSuperlayer() }

        puff(at: lp, in: root, size: 50, duration: 0.5)
        burst(at: lp, in: root, count: 7, speed: 260, color: NSColor(white: 0.9, alpha: 1))
    }

    private func puff(at lp: CGPoint, in root: CALayer, size: CGFloat, duration: Double) {
        let s = CALayer()
        s.contents = FXAssets.smoke
        s.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        s.position = lp
        s.opacity = 0
        root.addSublayer(s)
        let sc = CABasicAnimation(keyPath: "transform.scale"); sc.fromValue = 0.4; sc.toValue = 1.6
        let op = CAKeyframeAnimation(keyPath: "opacity"); op.values = [0, 0.7, 0]; op.keyTimes = [0, 0.15, 1]
        let mv = CABasicAnimation(keyPath: "position.y"); mv.toValue = lp.y + size * 0.3
        run([sc, op, mv], on: s, duration: duration, timing: Self.easeOutCubic)
    }

    /// 粒子火花：CAEmitterLayer 只喷一下
    private func burst(at lp: CGPoint, in root: CALayer, count: Int, speed: CGFloat, color: NSColor?) {
        let e = CAEmitterLayer()
        e.emitterPosition = lp
        e.emitterShape = .point
        e.renderMode = .additive
        let cell = CAEmitterCell()
        cell.contents = FXAssets.streak
        cell.birthRate = Float(count) * 25
        cell.lifetime = 0.32
        cell.lifetimeRange = 0.12
        cell.velocity = speed
        cell.velocityRange = speed * 0.5
        cell.emissionRange = .pi * 2
        cell.yAcceleration = -1400
        cell.scale = 0.42
        cell.scaleRange = 0.2
        cell.scaleSpeed = -0.6
        cell.alphaSpeed = -2.8
        if let color { cell.color = color.cgColor }
        // 让细长火花沿飞行方向
        cell.spin = 0
        e.emitterCells = [cell]
        e.beginTime = CACurrentMediaTime()
        root.addSublayer(e)
        after(0.04) { e.birthRate = 0 }
        after(0.6) { e.removeFromSuperlayer() }
    }

    enum MarkerKind { case body, head, kill }

    /// 命中标记（准星周围的 ×）
    func hitMarker(at p: CGPoint, kind: MarkerKind) {
        guard let (root, lp) = host(for: p) else { return }
        let l = CALayer()
        l.position = lp
        let color: NSColor = kind == .kill ? NSColor(red: 1, green: 0.16, blue: 0.16, alpha: 1)
            : kind == .head ? NSColor(red: 1, green: 0.84, blue: 0.3, alpha: 1) : .white
        let inner: CGFloat = kind == .kill ? 9 : 7, outer: CGFloat = kind == .kill ? 22 : 16
        for (dx, dy) in [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: dx * inner, y: dy * inner))
            path.addLine(to: CGPoint(x: dx * outer, y: dy * outer))
            let shadow = CAShapeLayer()
            shadow.path = path; shadow.lineWidth = kind == .kill ? 5.5 : 4.5; shadow.lineCap = .round
            shadow.strokeColor = NSColor(white: 0, alpha: 0.55).cgColor
            let s = CAShapeLayer()
            s.path = path; s.lineWidth = kind == .kill ? 3 : 2.2; s.lineCap = .round
            s.strokeColor = color.cgColor
            l.addSublayer(shadow); l.addSublayer(s)
        }
        root.addSublayer(l)
        let sc = CAKeyframeAnimation(keyPath: "transform.scale")
        sc.values = kind == .kill ? [1.9, 0.95, 1.0, 1.0] : [1.5, 1.0, 1.0]
        sc.keyTimes = kind == .kill ? [0, 0.12, 0.2, 1] : [0, 0.25, 1]
        let op = CAKeyframeAnimation(keyPath: "opacity"); op.values = [1, 1, 0]; op.keyTimes = [0, 0.55, 1]
        var anims: [CAAnimation] = [sc, op]
        if kind == .kill {
            let rot = CABasicAnimation(keyPath: "transform.rotation.z"); rot.fromValue = -0.35; rot.toValue = 0
            rot.duration = 0.12
            anims.append(rot)
        }
        run(anims, on: l, duration: kind == .kill ? 0.55 : 0.28, timing: nil)
    }

    // MARK: - target reactions

    /// 被击中：第一帧闪白 → 红色剪影；朝子弹方向被“打退”一下再弹回
    func damageFlash(_ t: Target, image: NSImage?, from aim: CGPoint) {
        guard let (root, r) = host(for: t.iconRect) else { return }
        let l = CALayer()
        l.frame = r
        root.addSublayer(l)
        guard let img = image, let red = img.redTinted(), let white = img.whiteFlash() else {
            l.backgroundColor = NSColor.systemRed.withAlphaComponent(0.6).cgColor
            l.cornerRadius = r.width * 0.22
            run([fadeOut(0.3)], on: l, duration: 0.3, timing: nil)
            return
        }
        l.contents = red
        let c = CABasicAnimation(keyPath: "contents"); c.fromValue = white; c.toValue = red; c.duration = 0.05
        l.add(c, forKey: nil)
        let center = CGPoint(x: t.iconRect.midX, y: t.iconRect.midY)
        var dx = center.x - aim.x, dy = center.y - aim.y
        let len = max(hypot(dx, dy), 0.001)
        dx /= len; dy /= len
        if len < 3 { dx = 0; dy = -1 }
        let kb: CGFloat = 7
        let pos = l.position
        // 屏幕坐标 y 向下，layer 坐标 y 向上
        let knock = CGPoint(x: pos.x + dx * kb, y: pos.y - dy * kb)
        let mv = CAKeyframeAnimation(keyPath: "position")
        mv.values = [pos, knock, CGPoint(x: pos.x - dx * 2, y: pos.y + dy * 2), pos].map { NSValue(point: $0) }
        mv.keyTimes = [0, 0.18, 0.5, 1]
        let sc = CAKeyframeAnimation(keyPath: "transform.scale"); sc.values = [1.16, 0.95, 1.0]; sc.keyTimes = [0, 0.4, 1]
        let op = CAKeyframeAnimation(keyPath: "opacity"); op.values = [1, 0.85, 0]; op.keyTimes = [0, 0.45, 1]
        run([mv, sc, op], on: l, duration: 0.32, timing: Self.easeOutCubic)
    }

    func damageNumber(_ dmg: Int, headshot: Bool, over t: Target) {
        guard let (root, r) = host(for: t.iconRect) else { return }
        let l = CATextLayer()
        let color = headshot ? NSColor(red: 1, green: 0.84, blue: 0.3, alpha: 1) : NSColor.white
        let font = NSFont(name: "AvenirNext-HeavyItalic", size: headshot ? 34 : 26)
            ?? .systemFont(ofSize: headshot ? 34 : 26, weight: .black)
        let str = NSMutableAttributedString(string: "\(dmg)", attributes: [
            .font: font, .foregroundColor: color,
            .strokeColor: NSColor(white: 0, alpha: 0.85), .strokeWidth: -3.5,
        ])
        if headshot {
            str.insert(NSAttributedString(string: "爆头 ", attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .heavy), .foregroundColor: color,
                .strokeColor: NSColor(white: 0, alpha: 0.85), .strokeWidth: -4,
            ]), at: 0)
        }
        l.string = str
        l.alignmentMode = .center
        l.contentsScale = 2
        l.frame = CGRect(x: 0, y: 0, width: 200, height: 44)
        let x0 = min(max(r.midX, 110), root.bounds.width - 110) + .random(in: -16...16)
        let y0 = min(r.maxY + 2, root.bounds.height - 60)
        l.position = CGPoint(x: x0, y: y0)
        root.addSublayer(l)
        let up = CABasicAnimation(keyPath: "position")
        up.toValue = NSValue(point: CGPoint(x: x0 + .random(in: -14...14), y: y0 + 46))
        up.timingFunction = Self.easeOutCubic
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.4, headshot ? 1.45 : 1.25, 1, 0.9]; pop.keyTimes = [0, 0.12, 0.28, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [1, 1, 0]; fade.keyTimes = [0, 0.65, 1]
        run([up, pop, fade], on: l, duration: 0.85, timing: nil)
    }

    /// 血条：主条立刻缩，后面的“残血”白条延迟追上（格斗/FPS 常见做法）
    func showHP(_ t: Target, hp: Int, maxHP: Int, label: String, pinned: Bool = false) {
        guard let (root, r) = host(for: t.iconRect) else { return }
        let bar = hpBars[t.id] ?? { let b = HPBarLayer(); hpBars[t.id] = b; return b }()
        if pinned { hpPinned.insert(t.id) }
        if bar.superlayer !== root { bar.removeFromSuperlayer(); root.addSublayer(bar) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let w = max(r.width + 30, 96, CGFloat(label.count) * 7.5 + 40)
        let bx = min(max(r.midX - w / 2, 6), root.bounds.width - w - 6)
        let by = pinned ? r.minY - 84 : min(r.maxY + 6, root.bounds.height - 34)
        bar.frame = CGRect(x: bx, y: by, width: w, height: 28)
        CATransaction.commit()
        if bar.opacity < 1 {
            bar.opacity = 1
            let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = 0; a.duration = 0.12
            bar.add(a, forKey: nil)
        }
        bar.update(ratio: CGFloat(hp) / CGFloat(max(maxHP, 1)), name: label, hp: hp, maxHP: maxHP)
        hpHideWork[t.id]?.cancel()
        guard !hpPinned.contains(t.id) else { return }
        let work = DispatchWorkItem { [weak bar] in
            CATransaction.begin(); CATransaction.setAnimationDuration(0.35); bar?.opacity = 0; CATransaction.commit()
        }
        hpHideWork[t.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// 阵亡：血条清空后立刻淡出移除，不再常驻
    func killHP(_ id: String) {
        hpHideWork[id]?.cancel(); hpHideWork[id] = nil
        hpPinned.remove(id)
        guard let bar = hpBars.removeValue(forKey: id) else { return }
        after(0.18) {
            let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = bar.presentation()?.opacity ?? 1; a.toValue = 0
            a.duration = 0.2; a.timingFunction = Self.easeOutCubic
            CATransaction.begin(); CATransaction.setDisableActions(true); bar.opacity = 0; CATransaction.commit()
            bar.add(a, forKey: "out")
            self.after(0.22) { bar.removeFromSuperlayer() }
        }
    }

    func hideHP(_ id: String) {
        hpPinned.remove(id)
        hpBars[id]?.removeFromSuperlayer()
        hpBars[id] = nil
    }

    // MARK: - death

    /// 阵亡：红色 → 去色变灰，并保持灰色直到复活
    func grayOut(_ t: Target, image: NSImage?) {
        guard let (root, r) = host(for: t.iconRect) else { return }
        deadLayers[t.id]?.removeFromSuperlayer()
        let l = CALayer()
        l.frame = r
        if let gray = image?.grayscale() {
            l.contents = gray
            if let red = image?.redTinted() {
                let c = CABasicAnimation(keyPath: "contents"); c.fromValue = red; c.toValue = gray
                c.duration = 0.45; c.timingFunction = Self.easeOutCubic
                l.add(c, forKey: nil)
            }
        } else {
            l.backgroundColor = NSColor(white: 0.3, alpha: 0.85).cgColor
            l.cornerRadius = r.width * 0.22
        }
        // 小裂纹，让“死掉”更明确，又不遮挡图标
        let cracks = CAShapeLayer()
        cracks.frame = l.bounds
        cracks.path = Self.crackPath(in: l.bounds, seed: t.id.hashValue)
        cracks.strokeColor = NSColor(white: 1, alpha: 0.55).cgColor
        cracks.fillColor = nil
        cracks.lineWidth = 1.2
        cracks.lineJoin = .round
        l.addSublayer(cracks)
        root.addSublayer(l)
        let sc = CAKeyframeAnimation(keyPath: "transform.scale")
        sc.values = [1.22, 0.92, 1.03, 1]; sc.keyTimes = [0, 0.3, 0.6, 1]
        sc.duration = 0.4; sc.timingFunction = Self.easeOutCubic
        l.add(sc, forKey: nil)
        let draw = CABasicAnimation(keyPath: "strokeEnd"); draw.fromValue = 0; draw.toValue = 1
        draw.duration = 0.18; draw.beginTime = CACurrentMediaTime() + 0.06; draw.fillMode = .backwards
        cracks.add(draw, forKey: nil)
        deadLayers[t.id] = l
    }

    func revive(_ id: String) {
        guard let l = deadLayers.removeValue(forKey: id) else { return }
        let sc = CAKeyframeAnimation(keyPath: "transform.scale"); sc.values = [1, 1.15, 1]
        let op = CAKeyframeAnimation(keyPath: "opacity"); op.values = [1, 0.6, 0]
        run([sc, op], on: l, duration: 0.35, timing: Self.easeOutCubic)
    }

    func reviveAll() { deadLayers.keys.forEach(revive) }

    private static func crackPath(in b: CGRect, seed: Int) -> CGPath {
        var rng = SeededRandom(seed: UInt64(bitPattern: Int64(seed)))
        let p = CGMutablePath()
        let c = CGPoint(x: b.midX + b.width * 0.1, y: b.midY + b.height * 0.08)
        for i in 0..<5 {
            var a = Double(i) / 5 * 2 * .pi + rng.next(-0.4, 0.4)
            var pt = c
            p.move(to: pt)
            for _ in 0..<3 {
                let step = b.width * CGFloat(rng.next(0.1, 0.18))
                a += rng.next(-0.5, 0.5)
                pt = CGPoint(x: pt.x + cos(a) * step, y: pt.y + sin(a) * step)
                p.addLine(to: pt)
            }
        }
        return p
    }

    /// 文件阵亡：变灰 → 抬起 → 沿弧线翻滚着飞进废纸篓 → 废纸篓“吞”一下
    /// 轨迹按全局坐标计算，每块屏幕各画一份，所以桌面和 Dock 不在同一块屏幕时也能一路飞过去。
    func trashFly(_ t: Target, image: NSImage?, to trash: CGRect?, onArrive: @escaping () -> Void) {
        guard let (srcRoot, srcR) = host(for: t.iconRect) else { onArrive(); return }
        hideHP(t.id)
        let ir = t.iconRect
        let startAX = CGPoint(x: ir.midX, y: ir.midY)
        let main = mainScreenRect
        let endAX = trash.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: main.maxX - 60, y: main.maxY - 60)
        // 控制点：往主屏中心鼓出去，再整体抬高一点（AX 坐标 y 向下，所以“抬高”是减）
        let midAX = CGPoint(x: (startAX.x + endAX.x) / 2, y: (startAX.y + endAX.y) / 2)
        var tx = main.midX - midAX.x, ty = main.midY - midAX.y
        let tl = max(hypot(tx, ty), 1); tx /= tl; ty /= tl
        let bulge = min(460, hypot(endAX.x - startAX.x, endAX.y - startAX.y) * 0.4 + 160)
        let ctrlAX = CGPoint(x: midAX.x + tx * bulge, y: midAX.y + ty * bulge - 140)

        let gray = image?.grayscale(), red = image?.redTinted()
        let T = 1.35, flyStart = 0.42, flyDur = 0.85
        let now = CACurrentMediaTime()
        let endScale = min(1, (trash?.height ?? 44) / ir.height) * 0.55
        let spinTurns = (startAX.x < endAX.x ? -1.0 : 1.0) * 2 * .pi * 1.25
        let ghosts: [(Double, Float)] = [(0.045, 0.32), (0.025, 0.5), (0, 1)]

        for w in windows {
            let sf = w.screen.frame
            func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - sf.minX, y: primaryHeight - p.y - sf.minY) }
            let path = CGMutablePath()
            path.move(to: local(startAX))
            path.addQuadCurve(to: local(endAX), control: local(ctrlAX))
            let s = local(startAX)
            let frame = CGRect(x: s.x - ir.width / 2, y: s.y - ir.height / 2, width: ir.width, height: ir.height)

            for (delay, alpha) in ghosts {
                let l = CALayer()
                l.frame = frame
                if let gray { l.contents = gray } else {
                    l.backgroundColor = NSColor(white: 0.35, alpha: 1).cgColor; l.cornerRadius = ir.width * 0.2
                }
                l.shadowColor = NSColor.black.cgColor
                l.shadowOffset = CGSize(width: 0, height: -8)
                l.shadowRadius = 10
                w.root.addSublayer(l)
                let isMain = delay == 0

                if isMain, let red, let gray {
                    let c = CABasicAnimation(keyPath: "contents"); c.fromValue = red; c.toValue = gray
                    c.duration = 0.3; l.add(c, forKey: nil)
                }
                let sc = CAKeyframeAnimation(keyPath: "transform.scale")
                sc.values = [1.2, 0.93, 1.04, 1.13, endScale]
                sc.keyTimes = [0, 0.1, 0.2, NSNumber(value: flyStart / T), 1]
                sc.timingFunctions = [Self.easeOutCubic, Self.easeOutCubic, Self.easeOutCubic, Self.easeInOutCubic]
                sc.duration = T; sc.beginTime = now + delay
                sc.fillMode = .both; sc.isRemovedOnCompletion = false
                l.add(sc, forKey: "scale")

                let fly = CAKeyframeAnimation(keyPath: "position")
                fly.path = path
                fly.calculationMode = .paced
                fly.timingFunction = Self.easeInOutCubic
                fly.beginTime = now + flyStart + delay; fly.duration = flyDur
                fly.fillMode = .both; fly.isRemovedOnCompletion = false
                l.add(fly, forKey: "fly")

                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0; spin.toValue = spinTurns
                spin.timingFunction = Self.easeInOutCubic
                spin.beginTime = now + flyStart + delay; spin.duration = flyDur
                spin.fillMode = .both; spin.isRemovedOnCompletion = false
                l.add(spin, forKey: "spin")

                let sh = CAKeyframeAnimation(keyPath: "shadowOpacity")
                sh.values = [0, 0, 0.45, 0.3]; sh.keyTimes = [0, 0.2, 0.32, 1]
                sh.duration = T; sh.beginTime = now; sh.fillMode = .both; sh.isRemovedOnCompletion = false
                l.add(sh, forKey: nil)

                let op = CAKeyframeAnimation(keyPath: "opacity")
                let a = Double(alpha)
                op.values = isMain ? [1, 1, 1, 0] : [0, 0, a, a, 0]
                op.keyTimes = isMain ? [0, 0.9, 0.97, 1]
                    : [0, NSNumber(value: flyStart / T), NSNumber(value: (flyStart + 0.08) / T), 0.85, 0.93]
                op.duration = T + delay; op.beginTime = now; op.fillMode = .both; op.isRemovedOnCompletion = false
                l.add(op, forKey: "opacity")

                after(T + delay + 0.05) { l.removeFromSuperlayer() }
            }
        }

        let start = CGPoint(x: srcR.midX, y: srcR.midY)
        after(0.02) { [weak self] in self?.burst(at: start, in: srcRoot, count: 26, speed: 360, color: nil) }
        after(flyStart) { [weak self] in self?.puff(at: start, in: srcRoot, size: ir.width * 1.6, duration: 0.7) }
        after(flyStart + flyDur) { [weak self] in
            if let self, let (troot, tp) = self.host(for: endAX) {
                self.trashGulp(at: tp, in: troot, size: trash?.height ?? 44)
            }
            onArrive()
        }
    }

    private func trashGulp(at p: CGPoint, in root: CALayer, size: CGFloat) {
        let t = CALayer()
        if let full = NSImage(named: NSImage.trashFullName)?.cg128 { t.contents = full }
        t.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        t.position = p
        root.addSublayer(t)
        let sc = CAKeyframeAnimation(keyPath: "transform.scale")
        sc.values = [1, 1.35, 0.9, 1.06, 1]; sc.keyTimes = [0, 0.18, 0.45, 0.7, 1]
        let sq = CAKeyframeAnimation(keyPath: "transform.scale.y")
        sq.values = [1, 0.85, 1.08, 1]; sq.keyTimes = [0, 0.2, 0.5, 1]
        let op = CAKeyframeAnimation(keyPath: "opacity"); op.values = [1, 1, 0]; op.keyTimes = [0, 0.8, 1]
        run([sc, op], on: t, duration: 0.6, timing: Self.easeOutCubic)
        puff(at: p, in: root, size: size * 2.2, duration: 0.6)
        burst(at: p, in: root, count: 10, speed: 200, color: NSColor(white: 0.85, alpha: 1))

        // 提示文字
        let label = CATextLayer()
        label.string = NSAttributedString(string: "已移到废纸篓 · 可恢复", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .heavy), .foregroundColor: NSColor.white,
            .strokeColor: NSColor(white: 0, alpha: 0.85), .strokeWidth: -4,
        ])
        label.alignmentMode = .center
        label.contentsScale = 2
        label.frame = CGRect(x: min(max(p.x - 110, 8), root.bounds.width - 228), y: min(p.y + size * 0.75, root.bounds.height - 30), width: 220, height: 22)
        root.addSublayer(label)
        let mv = CABasicAnimation(keyPath: "position.x"); mv.fromValue = label.position.x + 20
        let lo = CAKeyframeAnimation(keyPath: "opacity"); lo.values = [0, 1, 1, 0]; lo.keyTimes = [0, 0.1, 0.8, 1]
        run([mv, lo], on: label, duration: 1.8, timing: Self.easeOutCubic)
    }

    // MARK: - HUD

    /// CS 风格击杀栏：一行「玩家名  [武器]  [爆头]  被击杀者」，几秒后淡出
    func killFeed(player: String, weapon: Weapon, victim: String, headshot: Bool) {
        guard let root = mainRoot else { return }
        let h: CGFloat = 30
        let font = NSFont(name: "DINCondensed-Bold", size: 19) ?? .systemFont(ofSize: 17, weight: .bold)
        let ct = NSColor(red: 0.6, green: 0.8, blue: 0.97, alpha: 1)      // CT 蓝
        let tCol = NSColor(red: 0.92, green: 0.8, blue: 0.47, alpha: 1)   // T 黄
        func label(_ s: String, _ c: NSColor) -> CATextLayer {
            let l = CATextLayer()
            let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c])
            l.string = str
            l.contentsScale = 2
            let w = ceil(str.size().width) + 2
            l.bounds = CGRect(x: 0, y: 0, width: w, height: h - 8)
            return l
        }
        func icon(_ img: CGImage?, height: CGFloat) -> CALayer? {
            guard let img else { return nil }
            let l = CALayer()
            l.contents = img
            l.contentsGravity = .resizeAspect
            let aspect = CGFloat(img.width) / CGFloat(max(img.height, 1))
            l.bounds = CGRect(x: 0, y: 0, width: height * aspect, height: height)
            return l
        }
        var parts: [CALayer] = [label(player, ct)]
        if let w = icon(weapon == .pistol ? FXAssets.kfPistol : FXAssets.kfRifle, height: 20) { parts.append(w) }
        else { parts.append(label(weapon == .pistol ? "🔫" : "▬▬", .white)) }
        if headshot, let hs = icon(FXAssets.kfHeadshot, height: 20) { parts.append(hs) }
        parts.append(label(victim, tCol))

        let pad: CGFloat = 10, spacing: CGFloat = 9
        let w = parts.reduce(0) { $0 + $1.bounds.width } + spacing * CGFloat(parts.count - 1) + pad * 2
        let item = CALayer()
        item.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        item.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
        item.cornerRadius = 3
        // 自己的击杀：红色描边（CS 里自己击杀的那条就是这样）
        item.borderColor = NSColor(red: 0.85, green: 0.12, blue: 0.12, alpha: 0.95).cgColor
        item.borderWidth = 1.5
        var x = pad
        for p in parts {
            p.position = CGPoint(x: x + p.bounds.width / 2, y: h / 2 - (p is CATextLayer ? 2 : 0))
            item.addSublayer(p)
            x += p.bounds.width + spacing
        }

        let right = root.bounds.width - 24
        let top = root.bounds.height - 56 - h / 2
        feed.insert(item, at: 0)
        for (i, l) in feed.enumerated() where i > 0 {
            CATransaction.begin(); CATransaction.setAnimationDuration(0.18)
            CATransaction.setAnimationTimingFunction(Self.easeOutCubic)
            l.position = CGPoint(x: right - l.bounds.width / 2, y: top - CGFloat(i) * (h + 4))
            CATransaction.commit()
        }
        while feed.count > 6 { feed.removeLast().removeFromSuperlayer() }
        item.position = CGPoint(x: right - w / 2, y: top)
        root.addSublayer(item)
        let fin = CABasicAnimation(keyPath: "opacity"); fin.fromValue = 0; fin.duration = 0.12
        item.add(fin, forKey: nil)
        after(5) { [weak self] in
            CATransaction.begin(); CATransaction.setAnimationDuration(0.5); item.opacity = 0; CATransaction.commit()
            self?.after(0.55) { item.removeFromSuperlayer(); self?.feed.removeAll { $0 === item } }
        }
    }

    /// AI Agent 被打：红色小字像血一样从图标上飞溅出去（"5小时额度 -1%"）
    func bloodText(_ s: String, over t: Target, big: Bool) {
        guard let (root, r) = host(for: t.iconRect) else { return }
        // 拆成两段：“5小时额度”小一号浅色，“-1%”大号亮红，远处一眼能看清
        let parts = s.split(separator: " ", maxSplits: 1).map(String.init)
        let head = parts.first ?? s, tail = parts.count > 1 ? parts[1] : ""
        let font = NSFont(name: "PingFangSC-Semibold", size: big ? 19 : 16) ?? .systemFont(ofSize: big ? 19 : 16, weight: .heavy)
        let numFont = NSFont(name: "AvenirNext-HeavyItalic", size: big ? 34 : 28) ?? .systemFont(ofSize: big ? 34 : 28, weight: .black)
        let str = NSMutableAttributedString(string: head + " ", attributes: [
            .font: font, .foregroundColor: NSColor(red: 1, green: 0.9, blue: 0.9, alpha: 1),
        ])
        str.append(NSAttributedString(string: tail, attributes: [
            .font: numFont, .foregroundColor: NSColor(red: 1, green: 0.23, blue: 0.2, alpha: 1), .baselineOffset: -2,
        ]))
        let size = str.size()
        // 深红黑色胶囊底 + 红描边：任何背景上都看得清，又像一滴血
        let l = CALayer()
        l.bounds = CGRect(x: 0, y: 0, width: ceil(size.width) + 22, height: ceil(size.height) + 6)
        l.backgroundColor = NSColor(red: 0.12, green: 0, blue: 0.01, alpha: 0.84).cgColor
        l.borderColor = NSColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 0.9).cgColor
        l.borderWidth = 1.5
        l.cornerRadius = l.bounds.height / 2
        l.shadowColor = NSColor.black.cgColor
        l.shadowOpacity = 0.6; l.shadowRadius = 5; l.shadowOffset = CGSize(width: 0, height: -2)
        let tl = CATextLayer()
        tl.string = str
        tl.contentsScale = 2
        tl.alignmentMode = .center
        tl.frame = CGRect(x: 0, y: 1, width: l.bounds.width, height: ceil(size.height) + 2)
        l.addSublayer(tl)

        let room = root.bounds.height - r.maxY
        let up: CGFloat = room > 160 ? 1 : -1
        let x0 = min(max(r.midX + .random(in: -18...18), size.width / 2 + 10), root.bounds.width - size.width / 2 - 10)
        let start = CGPoint(x: x0, y: up > 0 ? r.maxY + 6 : r.minY - 6)
        l.position = start
        root.addSublayer(l)
        let dir: CGFloat = Bool.random() ? 1 : -1
        // 弹出 → 慢慢往上飘（留足阅读时间）→ 最后淡出
        let drift = CABasicAnimation(keyPath: "position")
        drift.toValue = NSValue(point: CGPoint(x: start.x + dir * .random(in: 6...18), y: start.y + up * .random(in: 60...80)))
        drift.timingFunction = Self.easeOutCubic
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.35, big ? 1.28 : 1.15, 1, 1]; pop.keyTimes = [0, 0.07, 0.14, 1]
        pop.timingFunctions = [Self.easeOutCubic, Self.easeOutCubic, CAMediaTimingFunction(name: .linear)]
        let rot = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rot.values = [dir * -0.12, dir * 0.04, 0]; rot.keyTimes = [0, 0.14, 1]
        let op = CAKeyframeAnimation(keyPath: "opacity"); op.values = [1, 1, 0]; op.keyTimes = [0, 0.78, 1]
        run([drift, pop, rot, op], on: l, duration: 1.9, timing: nil)
        bloodSpray(at: CGPoint(x: r.midX, y: r.midY), in: root, dir: dir, count: big ? 22 : 14)
    }

    private func bloodSpray(at p: CGPoint, in root: CALayer, dir: CGFloat, count: Int) {
        let e = CAEmitterLayer()
        e.emitterPosition = p
        e.emitterShape = .point
        let cell = CAEmitterCell()
        cell.contents = FXAssets.bloodDrop
        cell.birthRate = Float(count) * 25
        cell.lifetime = 0.7
        cell.lifetimeRange = 0.25
        cell.velocity = 260
        cell.velocityRange = 140
        cell.emissionLongitude = dir > 0 ? .pi / 3 : .pi * 2 / 3
        cell.emissionRange = .pi / 2.2
        cell.yAcceleration = -900
        cell.scale = 0.22
        cell.scaleRange = 0.14
        cell.alphaSpeed = -1.2
        e.emitterCells = [cell]
        e.beginTime = CACurrentMediaTime()
        root.addSublayer(e)
        after(0.04) { e.birthRate = 0 }
        after(1.0) { e.removeFromSuperlayer() }
    }

    /// 击杀时屏幕边缘一圈红色脉冲
    func killVignette() {
        guard let root = mainRoot else { return }
        let v = vignette ?? {
            let g = CAGradientLayer()
            g.type = .radial
            g.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor(red: 0.9, green: 0, blue: 0, alpha: 0.55).cgColor]
            g.locations = [0, 0.62, 1]
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1.15, y: 1.15)
            g.opacity = 0
            root.insertSublayer(g, at: 0)
            vignette = g
            return g
        }()
        v.frame = root.bounds
        let a = CAKeyframeAnimation(keyPath: "opacity"); a.values = [0, 1, 0]; a.keyTimes = [0, 0.15, 1]
        a.duration = 0.55; a.timingFunction = Self.easeOutCubic
        v.add(a, forKey: "pulse")
    }

    func toast(_ s: String) {
        guard let root = mainRoot else { return }
        let l = text(s, size: 20, color: .white, weight: .heavy)
        l.alignmentMode = .center
        l.frame = CGRect(x: root.bounds.midX - 400, y: root.bounds.height - 120, width: 800, height: 30)
        root.addSublayer(l)
        let op = CAKeyframeAnimation(keyPath: "opacity"); op.values = [0, 1, 1, 0]; op.keyTimes = [0, 0.08, 0.8, 1]
        run([op], on: l, duration: 2.4, timing: nil)
    }

    // MARK: - helpers

    private func text(_ s: String, size: CGFloat, color: NSColor, weight: NSFont.Weight) -> CATextLayer {
        let l = CATextLayer()
        l.string = NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
            .strokeColor: NSColor(white: 0, alpha: 0.7), .strokeWidth: -2.5,
        ])
        l.contentsScale = 2
        return l
    }

    private func fadeOut(_ d: Double) -> CAAnimation {
        let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = 1; a.toValue = 0; a.duration = d; return a
    }

    private func run(_ anims: [CAAnimation], on l: CALayer, duration: Double, timing: CAMediaTimingFunction?) {
        let g = CAAnimationGroup()
        g.animations = anims
        g.duration = duration
        if let timing { g.timingFunction = timing }
        g.fillMode = .forwards
        g.isRemovedOnCompletion = false
        l.add(g, forKey: nil)
        after(duration + 0.05) { l.removeFromSuperlayer() }
    }

    private func after(_ s: Double, _ f: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f)
    }
}

// MARK: - layers

/// 四段式动态准星：开枪时四臂弹开，用弹簧动画收回
final class CrosshairLayer: CALayer {
    private var arms: [CAShapeLayer] = []
    private let dot = CAShapeLayer()
    private var hot = false
    private let gap: CGFloat = 6
    private let dirs: [(CGFloat, CGFloat)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    override init() {
        super.init()
        bounds = CGRect(x: -40, y: -40, width: 80, height: 80)
        for (dx, dy) in dirs {
            let arm = CAShapeLayer()
            let p = CGMutablePath()
            p.move(to: .zero); p.addLine(to: CGPoint(x: dx * 14, y: dy * 14))
            arm.path = p
            arm.lineWidth = 2.8
            arm.lineCap = .butt
            arm.shadowColor = NSColor.black.cgColor
            arm.shadowOpacity = 0.9; arm.shadowRadius = 1.2; arm.shadowOffset = .zero
            arm.position = CGPoint(x: dx * gap, y: dy * gap)
            addSublayer(arm)
            arms.append(arm)
        }
        dot.path = CGPath(ellipseIn: CGRect(x: -1.8, y: -1.8, width: 3.6, height: 3.6), transform: nil)
        dot.shadowColor = NSColor.black.cgColor; dot.shadowOpacity = 0.9; dot.shadowRadius = 1.2; dot.shadowOffset = .zero
        addSublayer(dot)
        setHot(false, force: true)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func setHot(_ h: Bool, force: Bool = false) {
        guard h != hot || force else { return }
        hot = h
        let c = (h ? NSColor(red: 1, green: 0.22, blue: 0.2, alpha: 1) : NSColor(red: 0.35, green: 1, blue: 0.55, alpha: 1)).cgColor
        CATransaction.begin(); CATransaction.setAnimationDuration(0.08)
        arms.forEach { $0.strokeColor = c }
        dot.fillColor = c
        CATransaction.commit()
    }

    func kick() {
        for (i, (dx, dy)) in dirs.enumerated() {
            let a = CASpringAnimation(keyPath: "position")
            a.fromValue = NSValue(point: CGPoint(x: dx * (gap + 11), y: dy * (gap + 11)))
            a.toValue = NSValue(point: CGPoint(x: dx * gap, y: dy * gap))
            a.mass = 0.6; a.stiffness = 420; a.damping = 16
            a.duration = a.settlingDuration
            arms[i].add(a, forKey: "kick")
        }
    }
}

final class HPBarLayer: CALayer {
    private let bg = CALayer()
    private let ghost = CALayer()
    private let fill = CALayer()
    private let shine = CALayer()
    private let nameL = CATextLayer()
    private let hpL = CATextLayer()
    private var ratio: CGFloat = 1

    override init() {
        super.init()
        bg.backgroundColor = NSColor(white: 0.02, alpha: 0.75).cgColor
        bg.borderColor = NSColor(white: 1, alpha: 0.35).cgColor
        bg.borderWidth = 1
        bg.cornerRadius = 2
        ghost.backgroundColor = NSColor(white: 1, alpha: 0.85).cgColor
        shine.backgroundColor = NSColor(white: 1, alpha: 0.25).cgColor
        for l in [nameL, hpL] { l.contentsScale = 2 }
        nameL.alignmentMode = .left
        hpL.alignmentMode = .right
        for l in [bg, ghost, fill, shine, nameL, hpL] { addSublayer(l) }
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func update(ratio newRatio: CGFloat, name: String, hp: Int, maxHP: Int) {
        let r = max(0, min(1, newRatio))
        let inner = bounds.width - 4
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bg.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 10)
        let attrs: (CGFloat) -> [NSAttributedString.Key: Any] = { size in [
            .font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: NSColor.white,
            .strokeColor: NSColor(white: 0, alpha: 0.8), .strokeWidth: -4,
        ]}
        nameL.string = NSAttributedString(string: name, attributes: attrs(11))
        nameL.frame = CGRect(x: 0, y: 11, width: bounds.width - 36, height: 16)
        hpL.string = NSAttributedString(string: "\(hp)", attributes: attrs(11))
        hpL.frame = CGRect(x: bounds.width - 36, y: 11, width: 36, height: 16)
        if ghost.frame.width == 0 || r > ratio { ghost.frame = CGRect(x: 2, y: 2, width: inner * r, height: 6) }
        let color: NSColor = r > 0.6 ? NSColor(red: 0.3, green: 0.95, blue: 0.45, alpha: 1)
            : r > 0.3 ? NSColor(red: 1, green: 0.78, blue: 0.2, alpha: 1) : NSColor(red: 1, green: 0.22, blue: 0.2, alpha: 1)
        CATransaction.commit()

        CATransaction.begin(); CATransaction.setAnimationDuration(0.07)
        fill.frame = CGRect(x: 2, y: 2, width: inner * r, height: 6)
        shine.frame = CGRect(x: 2, y: 5.5, width: inner * r, height: 2.5)
        fill.backgroundColor = color.cgColor
        CATransaction.commit()

        // 残血条延迟后追上
        let target = CGRect(x: 2, y: 2, width: inner * r, height: 6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            CATransaction.begin(); CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(Overlay.easeOutCubic)
            self?.ghost.frame = target
            CATransaction.commit()
        }
        // 掉血时整条轻微一抖
        if r < ratio {
            let s = CAKeyframeAnimation(keyPath: "position.x")
            s.values = [position.x, position.x + 3, position.x - 2, position.x]
            s.duration = 0.15
            add(s, forKey: "shake")
        }
        ratio = r
    }
}

struct SeededRandom {
    private var s: UInt64
    init(seed: UInt64) { s = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next(_ lo: Double, _ hi: Double) -> Double {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return lo + Double(s % 10_000) / 10_000 * (hi - lo)
    }
}
