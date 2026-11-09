import Foundation
import Network
import CryptoKit

/// 网页扳机：手机扫码用浏览器打开，不用装 App。
/// 一个 HTTPS 端口同时提供：网页本体、WebSocket（/ws）、以及 WebSocket 不通时的 HTTP 轮询兜底（POST /msg）。
/// 消息内容和 UDP 版完全一样（见 Protocol.swift），收到的每一行交给 onLine。
final class WebServer {
    static let port: UInt16 = 47480

    var onLine: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    private(set) var url: String?

    private var listener: NWListener?
    private var clients: [ObjectIdentifier: WebClient] = [:]
    /// 轮询模式下还没取走的下行消息
    private var pollQueue: [String] = []
    private var lastPoll = Date.distantPast
    let queue = DispatchQueue(label: "phonegun.web", qos: .userInteractive)

    func start() {
        let ips = Self.lanIPv4()
        let host = (ProcessInfo.processInfo.hostName as NSString).replacingOccurrences(of: ".local", with: "") + ".local"
        guard let identity = WebCert.identity(ips: ips, host: host),
              let secId = sec_identity_create(identity) else {
            onStatus?("网页扳机：证书生成失败"); return
        }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secId)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: tls, tcp: tcp)
        params.allowLocalEndpointReuse = true
        do {
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] st in
                if case .failed(let e) = st { self?.onStatus?("网页扳机启动失败：\(e)") }
            }
            l.start(queue: queue)
            listener = l
            if let ip = ips.first { url = "https://\(ip):\(Self.port)/" }
        } catch {
            onStatus?("网页扳机启动失败：\(error)")
        }
    }

    /// 发给所有网页扳机
    func broadcast(_ msg: String) {
        queue.async {
            for c in self.clients.values where c.isWebSocket { c.sendText(msg) }
            if Date().timeIntervalSince(self.lastPoll) < 3 {
                self.pollQueue.append(msg)
                if self.pollQueue.count > 50 { self.pollQueue.removeFirst() }
            }
        }
    }

    private func accept(_ conn: NWConnection) {
        let c = WebClient(conn: conn, server: self)
        clients[ObjectIdentifier(c)] = c
        c.start()
    }

    fileprivate func closed(_ c: WebClient) {
        clients[ObjectIdentifier(c)] = nil
        if c.isWebSocket, !clients.values.contains(where: { $0.isWebSocket }) {
            onStatus?("手机网页已断开")
        }
    }

    fileprivate func wsOpened() { onStatus?("手机网页已连接") }

    fileprivate func received(_ line: String) {
        for l in line.split(separator: "\n") where !l.isEmpty { onLine?(String(l)) }
    }

    fileprivate func takePolled() -> String {
        if Date().timeIntervalSince(lastPoll) > 3 { onStatus?("手机网页已连接（轮询）") }
        lastPoll = Date()
        defer { pollQueue.removeAll() }
        return pollQueue.joined(separator: "\n")
    }

    // MARK: - 静态资源

    fileprivate static let page: Data = {
        if let u = Bundle.main.url(forResource: "trigger", withExtension: "html"), let d = try? Data(contentsOf: u) { return d }
        return Data("<h1>trigger.html 没打包进 App</h1>".utf8)
    }()

    fileprivate static let reloadWav: Data? = {
        Bundle.main.url(forResource: "reload", withExtension: "wav").flatMap { try? Data(contentsOf: $0) }
    }()

    /// 局域网 IPv4，en0（通常是 Wi-Fi）排前面
    static func lanIPv4() -> [String] {
        var out: [(String, String)] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if ip.hasPrefix("169.254.") { continue }
            out.append((name, ip))
        }
        return out.sorted { a, b in (a.0 == "en0" ? 0 : 1, a.0) < (b.0 == "en0" ? 0 : 1, b.0) }.map(\.1)
    }
}

/// 连接日志：~/Library/Logs/PhoneGun/web.log，用来查“手机点了继续访问后半天才出来”这类时序问题
enum WebLog {
    private static let url: URL = {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PhoneGun")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("web.log")
    }()
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
    static func write(_ s: String) {
        let line = "\(fmt.string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: url) }
    }
}

/// 一条 TLS 连接：先按 HTTP 处理，遇到 WebSocket 升级就切成帧模式。
private final class WebClient {
    let conn: NWConnection
    unowned let server: WebServer
    private var buf = Data()
    private(set) var isWebSocket = false
    private let born = Date()
    private let tag = String(UInt32.random(in: 0...0xFFFF), radix: 16)
    private var ms: Int { Int(Date().timeIntervalSince(born) * 1000) }

    init(conn: NWConnection, server: WebServer) { self.conn = conn; self.server = server }

    func start() {
        conn.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready: WebLog.write("[\(self.tag)] TLS 就绪 +\(self.ms)ms \(self.conn.endpoint)")
            case .failed(let e): WebLog.write("[\(self.tag)] 失败 +\(self.ms)ms \(e)"); self.server.closed(self)
            case .cancelled: self.server.closed(self)
            default: break
            }
        }
        conn.start(queue: server.queue)
        read()
    }

    private func read() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            if let data { self.buf.append(data); self.process() }
            if done || err != nil { self.conn.cancel() } else { self.read() }
        }
    }

    private func process() {
        while true {
            let before = buf.count
            if isWebSocket { parseFrame() } else { parseHTTP() }
            if buf.count == before || buf.isEmpty { return }
        }
    }

    // MARK: HTTP

    private func parseHTTP() {
        guard let end = buf.range(of: Data("\r\n\r\n".utf8)) else { return }
        let head = String(decoding: buf[buf.startIndex..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let reqLine = lines.removeFirst().split(separator: " ")
        guard reqLine.count >= 2 else { conn.cancel(); return }
        var h: [String: String] = [:]
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            h[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let len = Int(h["content-length"] ?? "0") ?? 0
        let bodyStart = end.upperBound
        guard buf.count - (bodyStart - buf.startIndex) >= len else { return }
        let body = buf[bodyStart..<(bodyStart + len)]
        buf = Data(buf[(bodyStart + len)...])

        let method = String(reqLine[0]), path = String(reqLine[1].split(separator: "?").first ?? "/")
        if path != "/msg" { WebLog.write("[\(tag)] \(method) \(path) +\(ms)ms UA=\(h["user-agent"] ?? "-")") }
        if h["upgrade"]?.lowercased() == "websocket", let key = h["sec-websocket-key"] {
            let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
            send(Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n".utf8))
            isWebSocket = true
            server.wsOpened()
            return
        }
        switch (method, path) {
        case ("GET", "/"), ("GET", "/index.html"):
            respond(200, "text/html; charset=utf-8", WebServer.page)
        case ("GET", "/reload.wav"):
            if let d = WebServer.reloadWav { respond(200, "audio/wav", d) } else { respond(404, "text/plain", Data()) }
        case ("POST", "/msg"):
            server.received(String(decoding: body, as: UTF8.self))
            respond(200, "text/plain; charset=utf-8", Data(server.takePolled().utf8))
        default:
            respond(404, "text/plain", Data("not found".utf8))
        }
    }

    private func respond(_ code: Int, _ type: String, _ body: Data) {
        let text = code == 200 ? "OK" : "Not Found"
        var d = Data("HTTP/1.1 \(code) \(text)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: keep-alive\r\n\r\n".utf8)
        d.append(body)
        send(d)
    }

    // MARK: WebSocket

    private func parseFrame() {
        let b = [UInt8](buf.prefix(14))
        guard b.count >= 2 else { return }
        let opcode = b[0] & 0x0F
        let masked = b[1] & 0x80 != 0
        var len = Int(b[1] & 0x7F)
        var off = 2
        if len == 126 {
            guard b.count >= 4 else { return }
            len = Int(b[2]) << 8 | Int(b[3]); off = 4
        } else if len == 127 {
            guard b.count >= 10 else { return }
            len = (2..<10).reduce(0) { $0 << 8 | Int(b[$1]) }; off = 10
        }
        let maskOff = off
        if masked { off += 4 }
        guard buf.count >= off + len else { return }
        let all = [UInt8](buf.prefix(off + len))
        var payload = Array(all[off..<(off + len)])
        if masked {
            let m = Array(all[maskOff..<(maskOff + 4)])
            for i in payload.indices { payload[i] ^= m[i & 3] }
        }
        buf = Data(buf.dropFirst(off + len))
        switch opcode {
        case 0x1, 0x0: server.received(String(decoding: payload, as: UTF8.self))
        case 0x8: sendFrame(0x8, Data()); conn.cancel()
        case 0x9: sendFrame(0xA, Data(payload))
        default: break
        }
    }

    func sendText(_ s: String) { sendFrame(0x1, Data(s.utf8)) }

    private func sendFrame(_ opcode: UInt8, _ payload: Data) {
        var f = Data([0x80 | opcode])
        if payload.count < 126 { f.append(UInt8(payload.count)) }
        else if payload.count < 65536 { f.append(126); f.append(UInt8(payload.count >> 8)); f.append(UInt8(payload.count & 0xFF)) }
        else { f.append(127); for i in (0..<8).reversed() { f.append(UInt8((payload.count >> (i * 8)) & 0xFF)) } }
        f.append(payload)
        send(f)
    }

    private func send(_ d: Data) { conn.send(content: d, completion: .idempotent) }
}
