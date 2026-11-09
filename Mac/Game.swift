import Cocoa

/// 把瞄准、命中判定、血量、特效、音效、反馈串起来。
final class Game {
    let server = GameServer()
    let scanner = TargetScanner()
    let overlay = Overlay()
    let sounds = SoundBoard()

    // 设置（菜单栏里可改）
    var degreesAcrossScreen: Double = 40
    var invertX = false
    var invertY = false
    var trashOnKill = true
    var macGunshot = true
    var mouseMode = false { didSet { mouseModeChanged() } }
    /// 击杀栏里显示的玩家名
    var playerName = NSUserName()
    let quota = Quota()

    var onStatus: ((String) -> Void)?

    private(set) var aim = CGPoint.zero
    private var ref: (yaw: Double, pitch: Double)?
    private var lastRaw: (yaw: Double, pitch: Double)?
    private var fx = OneEuroFilter(minCutoff: 1.2, beta: 0.015)
    private var fy = OneEuroFilter(minCutoff: 1.2, beta: 0.015)

    private var hp: [String: Int] = [:]
    private var dead: Set<String> = []
    private let icons = IconSource()
    private var mouseMonitor: Any?
    private var keyMonitor: Any?

    func start() {
        let r = overlay.mainScreenRect
        aim = CGPoint(x: r.midX, y: r.midY)
        overlay.moveCrosshair(to: aim, onTarget: false)

        server.onAim = { [weak self] y, p in self?.handleAim(yaw: y, pitch: p) }
        server.onRecenter = { [weak self] in self?.recenter() }
        server.onFire = { [weak self] w in self?.fire(w) }
        server.onRevive = { [weak self] in self?.reviveAll() }
        server.onStatus = { [weak self] s in self?.onStatus?(s) }
        server.start()
        scanner.start()
        quota.start()
    }

    // MARK: - aiming

    func recenter() {
        if let raw = lastRaw { ref = raw }
        fx.reset(); fy.reset()
        let r = overlay.mainScreenRect
        setAim(CGPoint(x: r.midX, y: r.midY))
    }

    private func handleAim(yaw: Double, pitch: Double) {
        guard !mouseMode else { return }
        lastRaw = (yaw, pitch)
        if ref == nil { recenter(); return }
        guard let ref else { return }
        var dyaw = yaw - ref.yaw
        while dyaw > .pi { dyaw -= 2 * .pi }
        while dyaw < -.pi { dyaw += 2 * .pi }
        let dpitch = pitch - ref.pitch

        let main = overlay.mainScreenRect
        let pxPerRad = main.width / (degreesAcrossScreen * .pi / 180)
        let x = main.midX + (invertX ? 1 : -1) * dyaw * pxPerRad
        let y = main.midY + (invertY ? 1 : -1) * dpitch * pxPerRad

        let t = CACurrentMediaTime()
        setAim(CGPoint(x: fx.filter(x, t: t), y: fy.filter(y, t: t)))
    }

    private func setAim(_ p: CGPoint) {
        let b = overlay.bounds
        aim = CGPoint(x: min(max(p.x, b.minX), b.maxX - 1), y: min(max(p.y, b.minY), b.maxY - 1))
        let t = scanner.target(at: aim)
        // 准星一移上去就提前抓好图标真身，开枪时特效立刻能用
        if let t { icons.prefetch(t) }
        overlay.moveCrosshair(to: aim, onTarget: t.map { !dead.contains($0.id) } ?? false)
    }

    // MARK: - firing

    private func pan(_ x: CGFloat) -> Float {
        let b = overlay.bounds
        return Float((x - b.midX) / (b.width / 2)) * 0.8
    }

    func fire(_ weapon: Weapon) {
        overlay.recoil()
        if macGunshot { sounds.play(weapon == .pistol ? .gunshot : .rifleShot, volume: 0.5, pan: pan(aim.x)) }

        guard let t = scanner.target(at: aim), !dead.contains(t.id) else {
            overlay.miss(at: aim)
            server.send("M")
            return
        }

        let maxHP = maxHP(for: t)
        let icon = self.icon(for: t)
        let center = CGPoint(x: t.iconRect.midX, y: t.iconRect.midY)
        let headshot = hypot(aim.x - center.x, aim.y - center.y) < t.iconRect.width * 0.18
        let dmg = weapon.damage * (headshot ? 2 : 1)
        let left = max(0, (hp[t.id] ?? maxHP) - dmg)
        hp[t.id] = left

        overlay.impact(at: aim, scale: headshot ? 1.3 : 1)
        overlay.damageFlash(t, image: icon, from: aim)
        if let agent = t.agent {
            // AI Agent：飞出“额度”血字；Codex / Antigravity 在后台真烧额度
            overlay.bloodText(headshot ? "周额度 -1%" : "5小时额度 -1%", over: t, big: headshot)
            if let q = agent.quota { quota.burn(q) }
            overlay.showHP(t, hp: left, maxHP: maxHP, label: hpLabel(t, agent: agent))
        } else {
            overlay.damageNumber(dmg, headshot: headshot, over: t)
            overlay.showHP(t, hp: left, maxHP: maxHP, label: t.title)
        }

        if left > 0 {
            overlay.hitMarker(at: aim, kind: headshot ? .head : .body)
            sounds.play(headshot ? .headshot : .hit, volume: 0.9, pan: pan(aim.x))
            server.send("H \(dmg) \(headshot ? 1 : 0)")
        } else {
            kill(t, icon: icon, headshot: headshot, weapon: weapon)
        }
    }

    /// Agent 血条标题：带上真实剩余额度
    private func hpLabel(_ t: Target, agent: (name: String, quota: Quota.Agent?)) -> String {
        guard let q = agent.quota, let st = quota.status[q] else { return agent.name + " · 额度" }
        var parts = [agent.name]
        if let f = st.fiveHourLeft { parts.append("5h \(Int(f))%") }
        if let w = st.weeklyLeft { parts.append("周 \(Int(w))%") }
        return parts.joined(separator: " · ")
    }

    private func kill(_ t: Target, icon: NSImage?, headshot: Bool, weapon: Weapon) {
        dead.insert(t.id)
        overlay.killHP(t.id)
        overlay.hitMarker(at: aim, kind: .kill)
        overlay.killVignette()
        overlay.killFeed(player: playerName, weapon: weapon, victim: t.agent?.name ?? t.title, headshot: headshot)
        sounds.play(.kill, volume: 0.9, pan: pan(aim.x))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.sounds.play(.killDing, volume: 0.7) }
        server.send("K \(t.title)")

        if t.isTrashableDesktopFile, trashOnKill, let url = t.url {
            // 真正的删除（移到废纸篓）立刻做，Finder 里的原图标会被我们画的副本挡住，观众看到的是它“飞走”
            NSWorkspace.shared.recycle([url]) { [weak self] _, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        self.overlay.toast("没扔进废纸篓：\(error.localizedDescription)")
                        self.dead.remove(t.id)
                        self.hp[t.id] = nil
                    }
                    self.scanner.rescan()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { self.sounds.play(.whoosh, volume: 0.8, pan: 0.3) }
            overlay.trashFly(t, image: icon, to: scanner.trashFrame) { [weak self] in
                self?.sounds.play(.trashThud, volume: 1, pan: 0.8)
                // 等 Finder 把图标真正移走后再清状态（之后同名新文件可以再打）
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.dead.remove(t.id); self?.hp[t.id] = nil
                }
            }
        } else {
            // Dock 应用 / 非桌面文件：变灰阵亡，直到“全部复活”
            overlay.grayOut(t, image: icon)
        }
    }

    func reviveAll() {
        overlay.reviveAll()
        for id in dead {
            hp[id] = nil
            overlay.hideHP(id)
        }
        dead.removeAll()
        sounds.play(.reload, volume: 0.8)
        overlay.toast("全部复活")
    }

    // MARK: - targets

    func maxHP(for t: Target) -> Int {
        if t.agent != nil { return 150 }
        guard t.kind == .desktop, let url = t.url else { return 100 }
        let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if vals?.isDirectory == true { return 150 }
        let mb = Double(vals?.fileSize ?? 0) / 1_000_000
        switch mb {
        case ..<1: return 75
        case ..<100: return 100
        case ..<1000: return 150
        default: return 250
        }
    }

    private func icon(for t: Target) -> NSImage? { icons.icon(for: t) }

    // MARK: - mouse test mode（没有手机时用鼠标瞄准，⌃⌥空格 开火）

    private func mouseModeChanged() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
        guard mouseMode else { return }
        let h = NSScreen.screens.first?.frame.height ?? 0
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            let p = NSEvent.mouseLocation
            self?.setAim(CGPoint(x: p.x, y: h - p.y))
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 49, e.modifierFlags.contains([.control, .option]) { self?.fire(.pistol) }
        }
    }
}
