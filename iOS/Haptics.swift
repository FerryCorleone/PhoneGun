import CoreHaptics
import UIKit

/// 开枪后坐力、命中、爆头、击杀各一种震动
final class Haptics {
    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = false
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    private func play(_ events: [CHHapticEvent]) {
        guard let engine, let p = try? CHHapticPattern(events: events, parameters: []) else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(); return
        }
        try? engine.makePlayer(with: p).start(atTime: 0)
    }

    private func tap(_ t: Double, _ intensity: Float, _ sharp: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: intensity),
            .init(parameterID: .hapticSharpness, value: sharp),
        ], relativeTime: t)
    }

    private func buzz(_ t: Double, _ d: Double, _ intensity: Float, _ sharp: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            .init(parameterID: .hapticIntensity, value: intensity),
            .init(parameterID: .hapticSharpness, value: sharp),
        ], relativeTime: t, duration: d)
    }

    func shot(_ w: Weapon) {
        if w == .pistol { play([tap(0, 1, 0.75), buzz(0.005, 0.06, 0.7, 0.2)]) }
        else { play([tap(0, 0.85, 0.6), buzz(0.004, 0.035, 0.5, 0.2)]) }
    }
    func hit() { play([tap(0, 0.8, 1)]) }
    func headshot() { play([tap(0, 1, 1), tap(0.07, 1, 1)]) }
    func kill() { play([tap(0, 1, 1), buzz(0.02, 0.35, 1, 0.1), tap(0.4, 0.8, 0.5)]) }
    func empty() { play([tap(0, 0.35, 1)]) }
    func reload() { play([tap(0.03, 0.8, 0.9), tap(0.31, 1, 1), tap(0.47, 0.9, 0.7)]) }
}
