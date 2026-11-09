import Cocoa
import ApplicationServices
import CoreImage

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let game = Game()
    private var statusItem: NSStatusItem!
    private var statusLine = "启动中…"

    private var trusted = false
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 从安装盘（DMG）里直接打开时，系统会把 App 放到临时路径运行，权限对它不生效，图标就打不了
        if Self.runningFromDiskImage {
            WebLog.write("启动：从安装盘运行 \(Bundle.main.bundlePath)")
            askToMoveToApplications()
            return
        }

        // 需要“设备控制和数据访问”权限（旧版 macOS 叫“辅助功能”）才能拿到 Dock / 桌面图标位置
        trusted = AXIsProcessTrusted()
        WebLog.write("启动：路径=\(Bundle.main.bundlePath) 设备控制权限=\(trusted)")
        if !trusted {
            statusLine = "还没有「\(Self.permissionName)」权限，打不了图标"
            // 用户在系统设置里打开开关后，自动接上，不用重启
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
                guard let self, AXIsProcessTrusted() else { return }
                t.invalidate()
                self.trusted = true
                self.statusLine = "权限已打开，可以开打了"
                WebLog.write("设备控制权限已授予")
                self.game.scanner.rescan()
                self.showReady()
            }
            DispatchQueue.main.async { self.askForPermission() }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌖"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        game.onStatus = { [weak self] s in
            self?.statusLine = s
            self?.statusItem.button?.title = s.contains("已连接") ? "⌖●" : "⌖"
        }
        game.start()

        if CommandLine.arguments.contains("--mouse") { game.mouseMode = true }
    }

    static var runningFromDiskImage: Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/")
    }

    private func askToMoveToApplications() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "请先把 PhoneGun 拖进「应用程序」文件夹"
        a.informativeText = "现在是直接从安装盘里打开的，这样 macOS 不会给它「\(Self.permissionName)」权限，打不了桌面上的图标。\n\n在安装窗口里，把 PhoneGun 图标拖到右边的「应用程序」文件夹，然后从「应用程序」里打开 PhoneGun。"
        a.addButton(withTitle: "打开「应用程序」文件夹")
        a.addButton(withTitle: "退出")
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
        NSApp.terminate(nil)
    }

    /// 这个权限在不同 macOS 版本里名字不一样（比如 macOS 27 中文叫“设备控制和数据访问”，以前叫“辅助功能”），
    /// 直接从系统设置自己的翻译里读，保证和用户看到的一致
    static let permissionName: String = {
        let fallback = "辅助功能"
        guard let b = Bundle(path: "/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex") else { return fallback }
        let langs = Bundle.preferredLocalizations(from: b.localizations, forPreferences: Locale.preferredLanguages)
        if #available(macOS 15.4, *) {
            let name = b.localizedString(forKey: "ACCESSIBILITY", value: fallback, table: "Localizable",
                                         localizations: langs.map { Locale.Language(identifier: $0) })
            return name.isEmpty ? fallback : name
        }
        return fallback
    }()

    /// 先用一个说人话的弹窗讲清楚要开哪个开关，再把 PhoneGun 加进系统列表并直接打开那一页
    private func askForPermission() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "还差一步：打开一个开关"
        a.informativeText = "PhoneGun 需要「\(Self.permissionName)」权限，才能知道桌面和 Dock 上的图标在哪儿。\n\n点「去打开」后会直接跳到对应的设置页，在列表里找到 PhoneGun，把它右边的开关打开就行。打开后马上生效，不用重启。"
        a.addButton(withTitle: "去打开")
        a.addButton(withTitle: "稍后")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        openAccessibilitySettings()
    }

    @objc private func openAccessibilitySettings() {
        // 带 prompt 调一次，系统才会把 PhoneGun 放进列表里（默认关着），用户只需要打开开关
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        let urls = ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
        for u in urls { if let url = URL(string: u), NSWorkspace.shared.open(url) { break } }
    }

    private func showReady() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "可以开打了 🎯"
        a.informativeText = "点菜单栏右上角的 ⌖，用 iPhone 相机扫里面的二维码，手机就变成枪了。"
        a.addButton(withTitle: "好")
        a.runModal()
    }

    @objc private func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let st = NSMenuItem(title: statusLine, action: nil, keyEquivalent: ""); st.isEnabled = false
        menu.addItem(st)
        if !trusted {
            menu.addItem(item("⚠️ 点这里打开「\(Self.permissionName)」权限（打开后就能打了）", #selector(openAccessibilitySettings)))
        } else {
            let n = game.scanner.targets.count
            let tc = NSMenuItem(title: "已识别目标：\(n) 个", action: nil, keyEquivalent: "")
            tc.isEnabled = false
            menu.addItem(tc)
            if n == 0 { menu.addItem(item("一个图标都没识别到？点这里重启 PhoneGun", #selector(relaunch))) }
        }
        menu.addItem(.separator())
        if let url = game.server.web.url {
            let t = NSMenuItem(title: "手机扫码当枪（不用装 App，和电脑连同一个 Wi-Fi）", action: nil, keyEquivalent: "")
            t.isEnabled = false
            menu.addItem(t)
            // 新版 macOS 菜单不再按原尺寸画 item.image，改用自定义 view 才能显示大图
            if let img = Self.qrImage(url, size: 200) {
                let box = NSView(frame: NSRect(x: 0, y: 0, width: img.size.width + 40, height: img.size.height + 12))
                let iv = NSImageView(frame: NSRect(x: 20, y: 6, width: img.size.width, height: img.size.height))
                iv.image = img
                iv.imageScaling = .scaleNone
                box.addSubview(iv)
                let qr = NSMenuItem()
                qr.view = box
                menu.addItem(qr)
            }
            for line in ["首次打开会提示「此连接非私人连接」：", "点「显示详细信息」→「访问此网站」即可"] {
                let i = NSMenuItem(title: line, action: nil, keyEquivalent: ""); i.isEnabled = false
                menu.addItem(i)
            }
            menu.addItem(item("复制链接 \(url)", #selector(copyWebURL)))
            menu.addItem(.separator())
        }
        menu.addItem(item("准星回中", #selector(recenter)))
        menu.addItem(item("全部复活", #selector(revive)))

        let sens = NSMenuItem(title: "灵敏度（转多少度扫过整屏）", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for d in [20.0, 30, 40, 55, 70] {
            let i = item("\(Int(d))°" + (d == 40 ? "（默认）" : ""), #selector(setSens(_:)))
            i.representedObject = d
            i.state = game.degreesAcrossScreen == d ? .on : .off
            sub.addItem(i)
        }
        sens.submenu = sub
        menu.addItem(sens)
        menu.addItem(toggle("左右反向", game.invertX, #selector(toggleInvertX)))
        menu.addItem(toggle("上下反向", game.invertY, #selector(toggleInvertY)))
        menu.addItem(.separator())
        for a in Quota.Agent.allCases {
            let st = game.quota.status[a]
            let f = st?.fiveHourLeft.map { "\(Int($0))%" } ?? "?"
            let w = st?.weeklyLeft.map { "\(Int($0))%" } ?? "?"
            let i = NSMenuItem(title: "\(a.rawValue) 剩余额度：5小时 \(f) · 周 \(w)  （烧额度任务 \(st?.running ?? 0) 个进行中）", action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        menu.addItem(toggle("打中 Codex / Antigravity 时真实消耗额度", game.quota.enabled, #selector(toggleBurn)))
        menu.addItem(item("刷新额度", #selector(refreshQuota)))
        menu.addItem(.separator())
        menu.addItem(toggle("击杀桌面文件后移到废纸篓", game.trashOnKill, #selector(toggleTrash)))
        menu.addItem(toggle("Mac 也播放枪声", game.macGunshot, #selector(toggleGunshot)))
        menu.addItem(toggle("鼠标测试模式（⌃⌥空格 开火）", game.mouseMode, #selector(toggleMouse)))
        menu.addItem(.separator())
        menu.addItem(item("退出 PhoneGun", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.target = self; return i
    }

    private func toggle(_ title: String, _ on: Bool, _ sel: Selector) -> NSMenuItem {
        let i = item(title, sel); i.state = on ? .on : .off; return i
    }

    @objc private func recenter() { game.recenter() }
    @objc private func revive() { game.reviveAll() }
    @objc private func toggleBurn() { game.quota.enabled.toggle() }
    @objc private func refreshQuota() { game.quota.refresh() }
    @objc private func setSens(_ s: NSMenuItem) { game.degreesAcrossScreen = s.representedObject as? Double ?? 40 }
    @objc private func toggleInvertX() { game.invertX.toggle() }
    @objc private func toggleInvertY() { game.invertY.toggle() }
    @objc private func toggleTrash() { game.trashOnKill.toggle() }
    @objc private func toggleGunshot() { game.macGunshot.toggle() }
    @objc private func toggleMouse() { game.mouseMode.toggle() }
    @objc private func copyWebURL() {
        guard let url = game.server.web.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    static func qrImage(_ text: String, size: CGFloat) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let ci = f.outputImage else { return nil }
        let scale = (size * 2 / ci.extent.width).rounded(.down)   // 2x 给 Retina，整数倍保持边缘锐利
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        // 加一圈白边，深色菜单里也能扫
        let img = NSImage(size: NSSize(width: size + 16, height: size + 16), flipped: false) { r in
            NSColor.white.setFill(); NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
            NSGraphicsContext.current?.imageInterpolation = .none
            NSGraphicsContext.current?.cgContext.draw(cg, in: r.insetBy(dx: 8, dy: 8))
            return true
        }
        return img
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
