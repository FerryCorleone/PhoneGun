import Cocoa
import ApplicationServices

/// 一个可以被打的目标（Dock 图标 或 桌面图标）。frame 用辅助功能坐标：左上角为原点、y 向下。
struct Target {
    enum Kind { case dock, desktop }
    let id: String
    let kind: Kind
    let title: String
    let frame: CGRect
    let url: URL?

    /// 只有真正位于 ~/Desktop 里的文件/文件夹才允许被扔进废纸篓
    var isTrashableDesktopFile: Bool {
        guard kind == .desktop, let url else { return false }
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").standardizedFileURL.path
        return url.standardizedFileURL.deletingLastPathComponent().path == desktop
            && FileManager.default.fileExists(atPath: url.path)
    }

    /// 是不是 AI Agent（打它扣“额度”）；quota 不为空的会真实消耗额度
    var agent: (name: String, quota: Quota.Agent?)? {
        guard kind == .dock else { return nil }
        let bid = url.flatMap { Bundle(url: $0)?.bundleIdentifier } ?? ""
        let t = title.lowercased()
        if bid == "com.openai.codex" || t == "codex" { return ("Codex", .codex) }
        if bid == "com.google.antigravity" || t.contains("antigravity") { return ("Antigravity", .antigravity) }
        if t.contains("grok") { return ("Grok Bot", nil) }
        if t == "muse" { return ("Muse", nil) }
        if bid == "com.anthropic.claudefordesktop" || t == "claude" { return ("Claude", nil) }
        if t.contains("豆包") || t.contains("doubao") { return ("豆包", nil) }
        if t.contains("workbuddy") { return ("WorkBuddy", nil) }
        return nil
    }

    /// 图标本体的方形区域（Dock 项的 frame 带了上下留白）
    var iconRect: CGRect {
        let s = min(frame.width, frame.height)
        return CGRect(x: frame.midX - s / 2, y: frame.midY - s / 2, width: s, height: s)
    }
}

/// 用辅助功能接口扫描 Dock 和 Finder 桌面上的图标位置。
final class TargetScanner {
    private(set) var targets: [Target] = []
    /// Dock 里废纸篓的位置（文件飞进去的终点）
    private(set) var trashFrame: CGRect?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "phonegun.scan", qos: .utility)
    var onUpdate: (() -> Void)?

    func start() {
        rescan()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.rescan() }
    }

    func rescan() {
        queue.async {
            let (dock, trash) = Self.scanDock()
            let found = dock + Self.scanDesktop()
            DispatchQueue.main.async {
                self.targets = found
                self.trashFrame = trash
                self.onUpdate?()
            }
        }
    }

    func target(at p: CGPoint) -> Target? {
        // 桌面图标优先（Dock 盖在桌面上时也只会命中 Dock 自身区域）
        return targets.first { $0.kind == .dock && $0.frame.contains(p) }
            ?? targets.first { $0.kind == .desktop && $0.frame.contains(p) }
    }

    // MARK: - AX helpers

    private static func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
    }

    private static func frame(of e: AXUIElement) -> CGRect? {
        guard let pv = attr(e, kAXPositionAttribute), let sv = attr(e, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &p)
        AXValueGetValue(sv as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] {
        attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func appElement(_ bundleID: String) -> AXUIElement? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            .map { AXUIElementCreateApplication($0.processIdentifier) }
    }

    private static func fileURL(_ e: AXUIElement) -> URL? {
        guard let u = attr(e, "AXURL") as? URL else { return nil }
        // 桌面图标给的是 file:///.file/id=… 这种引用 URL，要解析成真实路径
        return (u as NSURL).filePathURL ?? u
    }

    static func scanDock() -> ([Target], CGRect?) {
        guard let dock = appElement("com.apple.dock") else { return ([], nil) }
        var out: [Target] = []
        var trash: CGRect?
        for list in children(dock) where (attr(list, kAXRoleAttribute) as? String) == "AXList" {
            for item in children(list) {
                guard (attr(item, kAXRoleAttribute) as? String) == "AXDockItem",
                      let sub = attr(item, kAXSubroleAttribute) as? String,
                      sub != "AXSeparatorDockItem",
                      let f = frame(of: item), f.width > 4 else { continue }
                let title = attr(item, kAXTitleAttribute) as? String ?? "?"
                if sub == "AXTrashDockItem" { trash = f; continue }   // 废纸篓本身不当靶子
                out.append(Target(id: "dock:" + title, kind: .dock, title: title, frame: f, url: fileURL(item)))
            }
        }
        return (out, trash)
    }

    static func scanDesktop() -> [Target] {
        guard let finder = appElement("com.apple.finder") else { return [] }
        var out: [Target] = []
        for area in children(finder) where (attr(area, kAXRoleAttribute) as? String) == "AXScrollArea" {
            for group in children(area) {
                for icon in children(group) where (attr(icon, kAXRoleAttribute) as? String) == "AXImage" {
                    guard let f = frame(of: icon) else { continue }
                    let title = attr(icon, kAXTitleAttribute) as? String
                        ?? attr(icon, "AXFilename") as? String ?? "?"
                    let url = fileURL(icon)
                    // 刚被扔进废纸篓、Finder 还没来得及刷新的图标，不算目标
                    if let u = url, u.path.contains("/.Trash/") { continue }
                    out.append(Target(id: "desk:" + title, kind: .desktop,
                                      title: title, frame: f, url: url))
                }
            }
        }
        return out
    }
}
