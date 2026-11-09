import Cocoa
import ScreenCaptureKit
import QuickLookThumbnailing

/// 拿到和屏幕上“长得一模一样”的图标，用来做变红、变灰、飞走这些特效：
/// - Dock：直接截取屏幕上该图标的真实像素（排除我们自己的特效窗口），这样 App 运行时换的图标（比如 Codex 的紫色云）也对得上；
/// - 桌面文件：用 QuickLook 生成和 Finder 一样的缩略图（图片显示预览而不是通用图标）。
/// 拿不到时退回 NSWorkspace 的文件图标。
final class IconSource {
    private var cache: [String: NSImage] = [:]
    private var pending: Set<String> = []

    func icon(for t: Target) -> NSImage? {
        if let c = cache[t.id] { return c }
        prefetch(t)
        return fallback(t)
    }

    func invalidate(_ id: String) { cache[id] = nil }

    func prefetch(_ t: Target) {
        guard cache[t.id] == nil, !pending.contains(t.id) else { return }
        pending.insert(t.id)
        let done: (NSImage?) -> Void = { [weak self] img in
            DispatchQueue.main.async {
                self?.pending.remove(t.id)
                if let img { self?.cache[t.id] = img }
            }
        }
        switch t.kind {
        case .dock: Task { done(await Self.captureScreen(t.iconRect)) }
        case .desktop: thumbnail(t, done: done)
        }
    }

    private func fallback(_ t: Target) -> NSImage? {
        guard let url = t.url else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 256, height: 256)
        return img
    }

    private func thumbnail(_ t: Target, done: @escaping (NSImage?) -> Void) {
        guard let url = t.url else { done(nil); return }
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 256, height: 256), scale: 2,
                                               representationTypes: [.icon, .thumbnail])
        req.iconMode = true
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            done(rep.map { NSImage(cgImage: $0.cgImage, size: NSSize(width: 256, height: 256)) })
        }
    }

    /// 截取屏幕上一块区域（辅助功能坐标），排除本 App 的窗口，并裁成圆角方块
    static func captureScreen(_ axRect: CGRect) async -> NSImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
        let primaryH = await MainActor.run { NSScreen.screens.first?.frame.height ?? 0 }
        // 找包含该区域的显示器
        let center = CGPoint(x: axRect.midX, y: axRect.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(center) }) else { return nil }
        _ = primaryH
        let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        let local = axRect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        cfg.sourceRect = local
        let scale = CGFloat(filter.pointPixelScale)
        cfg.width = Int(local.width * scale)
        cfg.height = Int(local.height * scale)
        cfg.showsCursor = false
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else { return nil }
        return roundedMask(img)
    }

    /// Dock 图标是圆角方块：截图四角会带进 Dock 背景，裁掉
    private static func roundedMask(_ img: CGImage) -> NSImage {
        let w = img.width, h = img.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let inset = CGFloat(w) * 0.085
        let r = CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: inset, dy: inset)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: r.width * 0.225, cornerHeight: r.height * 0.225, transform: nil))
        ctx.clip()
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: 256, height: 256))
    }
}
