import Foundation
import Network

/// 通过 Bonjour 自动找到 Mac 上的 PhoneGun，并用 UDP 收发。
@MainActor
final class Link: ObservableObject {
    @Published var status = "正在寻找电脑…"
    @Published var connected = false
    var onMessage: ((String) -> Void)?

    private var browser: NWBrowser?
    private var conn: NWConnection?
    private let queue = DispatchQueue(label: "trigger.link", qos: .userInteractive)
    private var fireSeq = 0

    func start() {
        let b = NWBrowser(for: .bonjour(type: GunProtocol.serviceType, domain: nil), using: .udp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let first = results.first else { return }
            Task { @MainActor in self?.connect(to: first.endpoint) }
        }
        b.stateUpdateHandler = { [weak self] st in
            if case .failed(let e) = st { Task { @MainActor in self?.status = "搜索失败：\(e)" } }
        }
        b.start(queue: queue)
        browser = b
        // 心跳，让 Mac 端知道连接还在
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendRaw("P") }
        }
    }

    private func connect(to endpoint: NWEndpoint) {
        if conn != nil, connected { return }
        conn?.cancel()
        let params = NWParameters.udp
        params.serviceClass = .interactiveVoice   // 低延迟优先
        let c = NWConnection(to: endpoint, using: params)
        c.stateUpdateHandler = { [weak self] st in
            Task { @MainActor in
                switch st {
                case .ready:
                    self?.connected = true
                    self?.activeConnection = c
                    if case let .service(name, _, _, _) = endpoint {
                        self?.status = "已连接 \(name.replacingOccurrences(of: "PhoneGun-", with: ""))"
                    } else { self?.status = "已连接" }
                    self?.sendRaw("R")
                case .failed, .cancelled:
                    self?.connected = false
                    self?.activeConnection = nil
                    self?.status = "连接断开，重新寻找…"
                    self?.conn = nil
                default: break
                }
            }
        }
        c.start(queue: queue)
        conn = c
        receive(c)
    }

    private func receive(_ c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            if let data, let s = String(data: data, encoding: .utf8) {
                Task { @MainActor in self?.onMessage?(s) }
            }
            if error == nil { Task { @MainActor in self?.receive(c) } }
        }
    }

    /// 给陀螺仪线程直接用的连接引用（只在连接就绪/断开时改）
    nonisolated(unsafe) var activeConnection: NWConnection?

    func sendRaw(_ s: String) {
        conn?.send(content: s.data(using: .utf8), completion: .idempotent)
    }

    func fire(_ w: Weapon) {
        fireSeq += 1
        let msg = "F \(fireSeq) \(w.rawValue)"
        sendRaw(msg)
        // UDP 可能丢包：隔 15ms 再补发一次，Mac 端按 id 去重
        queue.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            Task { @MainActor in self?.sendRaw(msg) }
        }
    }
}
