import Foundation

/// 手机 ⇄ Mac 的 UDP 文本协议（一行一个包）
///
/// 手机 → Mac
///   A <yaw> <pitch>        当前朝向（弧度，世界坐标，Mac 端负责“回中”换算）
///   R                      回中：把当前朝向当作屏幕中心
///   F <id> <weapon>        开火（同一个 id 会连发两次防丢包，Mac 端去重）
///   P                      心跳
///   V                      全部复活
/// Mac → 手机
///   H <damage> <headshot>  命中
///   K <name>               击杀
///   M                      未命中
enum GunProtocol {
    static let serviceType = "_phonegun._udp"
    static let port: UInt16 = 47474
}

enum Weapon: String, CaseIterable, Identifiable {
    case pistol, rifle
    var id: String { rawValue }
    var damage: Int { self == .pistol ? 25 : 12 }
    var title: String { self == .pistol ? "手枪" : "步枪" }
    var magazine: Int { self == .pistol ? 15 : 45 }
    /// 自动连发间隔（秒），nil 表示半自动
    var autoInterval: Double? { self == .rifle ? 0.1 : nil }
}
