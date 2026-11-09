import Foundation
import Security

/// 网页扳机用的自签名 HTTPS 证书。
/// iOS Safari 只在 HTTPS 页面里给陀螺仪权限，所以局域网里也得走 HTTPS。
/// 证书放在 ~/Library/Application Support/PhoneGun/，局域网 IP 变了就重新生成。
enum WebCert {
    private static let pass = "phonegun"

    static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhoneGun", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// 生成（如有必要）并载入证书身份
    static func identity(ips: [String], host: String) -> SecIdentity? {
        let p12 = dir.appendingPathComponent("web.p12")
        let sanFile = dir.appendingPathComponent("web.san")
        let san = (ips.map { "IP:\($0)" } + ["DNS:\(host)", "DNS:localhost", "IP:127.0.0.1"]).joined(separator: ",")
        let old = try? String(contentsOf: sanFile, encoding: .utf8)
        if old != san || !FileManager.default.fileExists(atPath: p12.path) {
            guard generate(san: san, to: p12) else { return nil }
            try? san.write(to: sanFile, atomically: true, encoding: .utf8)
        }
        return load(p12)
    }

    private static func generate(san: String, to p12: URL) -> Bool {
        let key = dir.appendingPathComponent("web.key"), crt = dir.appendingPathComponent("web.crt")
        let ok1 = run(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256",
                       "-keyout", key.path, "-out", crt.path, "-days", "800",
                       "-subj", "/CN=PhoneGun",
                       "-addext", "subjectAltName=\(san)",
                       "-addext", "extendedKeyUsage=serverAuth"])
        let ok2 = ok1 && run(["pkcs12", "-export", "-inkey", key.path, "-in", crt.path,
                              "-out", p12.path, "-passout", "pass:\(pass)"])
        try? FileManager.default.removeItem(at: key)
        return ok2
    }

    private static func run(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return p.terminationStatus == 0
    }

    private static func load(_ p12: URL) -> SecIdentity? {
        guard let data = try? Data(contentsOf: p12) else { return nil }
        var opts: [String: Any] = [kSecImportExportPassphrase as String: pass]
        if #available(macOS 15.0, *) { opts[kSecImportToMemoryOnly as String] = true }
        var items: CFArray?
        guard SecPKCS12Import(data as CFData, opts as CFDictionary, &items) == errSecSuccess,
              let arr = items as? [[String: Any]],
              let id = arr.first?[kSecImportItemIdentity as String] else { return nil }
        return (id as! SecIdentity)
    }
}
