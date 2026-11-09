import Foundation

/// One Euro Filter：慢动作时强平滑（稳），快动作时几乎不平滑（不拖）。
struct OneEuroFilter {
    var minCutoff: Double = 1.0
    var beta: Double = 0.02
    var dCutoff: Double = 1.0
    private var x: Double?
    private var dx: Double = 0
    private var lastT: Double?

    init(minCutoff: Double = 1.0, beta: Double = 0.02) {
        self.minCutoff = minCutoff; self.beta = beta
    }

    private func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    mutating func reset() { x = nil; lastT = nil; dx = 0 }

    mutating func filter(_ value: Double, t: Double) -> Double {
        guard let px = x, let pt = lastT else { x = value; lastT = t; return value }
        let dt = max(t - pt, 1e-4)
        lastT = t
        let rawDx = (value - px) / dt
        dx += alpha(dCutoff, dt) * (rawDx - dx)
        let cutoff = minCutoff + beta * abs(dx)
        let nx = px + alpha(cutoff, dt) * (value - px)
        x = nx
        return nx
    }
}
