import SwiftUI
import AVFoundation

@main
struct TriggerApp: App {
    @StateObject private var gun = GunModel()
    var body: some Scene {
        WindowGroup {
            GunView().environmentObject(gun)
                .preferredColorScheme(.dark)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    gun.start()
                }
        }
    }
}

@MainActor
final class GunModel: ObservableObject {
    @Published var weapon: Weapon = .pistol { didSet { ammo = weapon.magazine } }
    @Published var ammo = Weapon.pistol.magazine
    @Published var reloading = false
    @Published var lastResult = ""
    @Published var hitFlash = 0       // 每次命中 +1，驱动界面闪烁
    @Published var hitKind = 0        // 0 身体 1 爆头 2 击杀
    @Published var kills = 0
    @Published var phoneGunshot = true

    let link = Link()
    private let aimer = Aimer()
    private let haptics = Haptics()
    private let sounds = SoundBoard()
    private var autoTimer: Timer?

    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        link.onMessage = { [weak self] m in self?.handle(m) }
        link.start()
        aimer.connection = { [weak link] in link?.activeConnection }
        aimer.onShake = { [weak self] in self?.reload(byShake: true) }
        aimer.start()
    }

    func recenter() {
        link.sendRaw("R")
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func reviveAll() {
        link.sendRaw("V")
        haptics.reload()
        lastResult = "全部复活"
    }

    func triggerDown() {
        fireOnce()
        if let interval = weapon.autoInterval {
            autoTimer?.invalidate()
            // 必须加到 .common 模式：手指按住时主线程处于触摸跟踪模式，默认模式的 Timer 不会触发（之前连发要等约 1 秒就是这个原因）
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.fireOnce() }
            }
            RunLoop.main.add(t, forMode: .common)
            autoTimer = t
        }
    }

    func triggerUp() { autoTimer?.invalidate(); autoTimer = nil }

    private func fireOnce() {
        guard !reloading else { return }
        guard ammo > 0 else {
            haptics.empty(); sounds.play(.empty); triggerUp()
            lastResult = "没子弹了，甩一下手机换弹"
            return
        }
        ammo -= 1
        link.fire(weapon)
        haptics.shot(weapon)
        if phoneGunshot { sounds.play(weapon == .pistol ? .gunshot : .rifleShot, volume: 0.9) }
        if ammo == 0 { triggerUp() }
    }

    func reload(byShake: Bool = false) {
        guard !reloading else { return }
        // 按钮换弹：满弹就不换；甩手换弹：满弹也给反馈，手感更爽
        guard byShake || ammo < weapon.magazine else { return }
        reloading = true
        triggerUp()
        haptics.reload(); sounds.play(.reload, volume: 1)
        lastResult = "换弹中…"
        // 等“插弹匣+拉套筒”这段声音快结束时再补满，声画对得上
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            self.ammo = self.weapon.magazine
            self.reloading = false
            self.lastResult = "换弹完成"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func handle(_ m: String) {
        let p = m.split(separator: " ", maxSplits: 2).map(String.init)
        switch p.first {
        case "H":
            let head = p.count > 2 && p[2] == "1"
            head ? haptics.headshot() : haptics.hit()
            lastResult = head ? "爆头！-\(p[1])" : "命中 -\(p.count > 1 ? p[1] : "")"
            hitKind = head ? 1 : 0
            hitFlash += 1
        case "K":
            haptics.kill()
            kills += 1
            lastResult = "击杀 \(p.count > 1 ? p[1...].joined(separator: " ") : "")"
            hitKind = 2
            hitFlash += 1
        case "M":
            lastResult = "未命中"
        default: break
        }
    }
}
