import Foundation
import Network

/// UDP 服务端：Bonjour 广播 + 固定端口，收手机的瞄准/开火包，回传命中反馈。
final class GameServer {
    var onAim: ((Double, Double) -> Void)?
    var onRecenter: (() -> Void)?
    var onFire: ((Weapon) -> Void)?
    var onRevive: (() -> Void)?
    var onStatus: ((String) -> Void)?

    private var listener: NWListener?
    private var current: NWConnection?
    private var lastFireIDs: [String] = []
    private let queue = DispatchQueue(label: "phonegun.server", qos: .userInteractive)
    /// 网页扳机（手机扫码用浏览器当枪，不用装 App）
    let web = WebServer()

    func start() {
        web.onLine = { [weak self] line in self?.queue.async { self?.handle(line) } }
        web.onStatus = { [weak self] s in self?.status(s) }
        web.start()
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: GunProtocol.port)!)
            l.service = NWListener.Service(name: "PhoneGun-\(Host.current().localizedName ?? "Mac")",
                                           type: GunProtocol.serviceType)
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            l.stateUpdateHandler = { [weak self] st in
                if case .failed(let e) = st { self?.status("监听失败：\(e)") }
                if case .ready = st { self?.status("等待手机连接…") }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            status("无法启动：\(error)")
        }
    }

    private func accept(_ conn: NWConnection) {
        if let old = current, old !== conn { old.cancel() }
        current = conn
        conn.stateUpdateHandler = { [weak self] st in
            if case .ready = st { self?.status("手机已连接") }
        }
        conn.start(queue: queue)
        receive(on: conn)
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let s = String(data: data, encoding: .utf8) { self.handle(s) }
            if error == nil { self.receive(on: conn) }
        }
    }

    private func handle(_ line: String) {
        let p = line.split(separator: " ")
        guard let cmd = p.first else { return }
        switch cmd {
        case "A" where p.count >= 3:
            if let y = Double(p[1]), let pi = Double(p[2]) {
                DispatchQueue.main.async { self.onAim?(y, pi) }
            }
        case "R":
            DispatchQueue.main.async { self.onRecenter?() }
        case "V":
            DispatchQueue.main.async { self.onRevive?() }
        case "F" where p.count >= 3:
            let id = String(p[1])
            guard !lastFireIDs.contains(id) else { return }
            lastFireIDs.append(id); if lastFireIDs.count > 32 { lastFireIDs.removeFirst() }
            let w = Weapon(rawValue: String(p[2])) ?? .pistol
            DispatchQueue.main.async { self.onFire?(w) }
        default: break
        }
    }

    func send(_ msg: String) {
        web.broadcast(msg)
        queue.async { [weak self] in
            self?.current?.send(content: msg.data(using: .utf8), completion: .idempotent)
        }
    }

    private func status(_ s: String) { DispatchQueue.main.async { self.onStatus?(s) } }
}
