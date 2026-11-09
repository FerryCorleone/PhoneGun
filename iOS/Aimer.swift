import CoreMotion
import Network

/// 读陀螺仪姿态，算出手机“顶端”指向的 yaw / pitch，100Hz 发给 Mac。
/// 用的是重力为 z 轴的世界坐标，所以横握竖握、手机有没有歪（roll）都不影响瞄准。
final class Aimer {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    var connection: () -> NWConnection? = { nil }
    /// 甩一下手机（换弹）
    var onShake: (() -> Void)?
    private var lastShake = Date.distantPast

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
        motion.deviceMotionUpdateInterval = 1.0 / 100.0
        // 纯陀螺仪+加速度计（不用磁力计），旁边有电脑和音箱也不会乱跳；慢漂移靠“回中”解决
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let m = dm.attitude.rotationMatrix
            // 甩手检测：用户加速度（去掉重力）超过 ~2.2g，且距离上次至少 0.9 秒
            let a = dm.userAcceleration
            let g = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            if g > 2.2, Date().timeIntervalSince(self.lastShake) > 0.9 {
                self.lastShake = Date()
                DispatchQueue.main.async { self.onShake?() }
            }
            // 设备 y 轴（手机顶端）在世界坐标里的方向 = 旋转矩阵第二行
            let px = m.m21, py = m.m22, pz = m.m23
            let yaw = atan2(py, px)
            let pitch = atan2(pz, (px * px + py * py).squareRoot())
            // 甩手换弹的那一下别把准星甩飞：之后 0.5 秒不发瞄准
            guard Date().timeIntervalSince(self.lastShake) > 0.5, let c = self.connection() else { return }
            c.send(content: String(format: "A %.5f %.5f", yaw, pitch).data(using: .utf8), completion: .idempotent)
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}
