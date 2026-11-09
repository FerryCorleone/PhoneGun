import Foundation

/// 真实额度：读取 Codex / Antigravity 的剩余额度，并在被击中时在后台跑高消耗任务去烧它们的 token。
final class Quota {
    enum Agent: String, CaseIterable { case codex = "Codex", antigravity = "Antigravity" }

    struct Status {
        var fiveHourLeft: Double?   // 剩余百分比 0-100
        var weeklyLeft: Double?
        var running = 0             // 正在烧的任务数
        var burned = 0              // 本次启动累计派出去的任务数
    }

    private(set) var status: [Agent: Status] = [.codex: Status(), .antigravity: Status()]
    var enabled = true
    var maxConcurrent = 3
    var onChange: (() -> Void)?

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let workDir: URL = FileManager.default.temporaryDirectory.appendingPathComponent("phonegun-burn")
    private var timer: Timer?
    private var refreshing: Set<Agent> = []

    private var env: [String: String] {
        var e = ProcessInfo.processInfo.environment
        let extra = ["\(home.path)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        e["PATH"] = (extra + [(e["PATH"] ?? "")]).joined(separator: ":")
        return e
    }

    func start() {
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }

    // MARK: - 读取额度

    func refresh() {
        refreshCodex()
        refreshAntigravity()
    }

    private func refreshCodex() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let root = self.home.appendingPathComponent(".codex/sessions")
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])?
                .compactMap({ $0 as? URL }).filter({ $0.pathExtension == "jsonl" }) else { return }
            let newest = files.sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }.prefix(5)
            for f in newest {
                guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
                    guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else { continue }
                    if let rl = Self.find("rate_limits", in: obj) as? [String: Any] {
                        let p = (rl["primary"] as? [String: Any])?["used_percent"] as? Double
                        let s = (rl["secondary"] as? [String: Any])?["used_percent"] as? Double
                        DispatchQueue.main.async {
                            self.status[.codex]?.fiveHourLeft = p.map { 100 - $0 }
                            self.status[.codex]?.weeklyLeft = s.map { 100 - $0 }
                            self.onChange?()
                        }
                        return
                    }
                }
            }
        }
    }

    private static func find(_ key: String, in obj: Any) -> Any? {
        if let d = obj as? [String: Any] {
            if let v = d[key], !(v is NSNull) { return v }
            for v in d.values { if let r = find(key, in: v) { return r } }
        } else if let a = obj as? [Any] {
            for v in a { if let r = find(key, in: v) { return r } }
        }
        return nil
    }

    /// `agy -p "/usage"` 输出制表符分隔：池子  名称  剩余%  重置时间
    private func refreshAntigravity() {
        guard !refreshing.contains(.antigravity) else { return }
        refreshing.insert(.antigravity)
        run(["agy", "-p", "/usage"], timeout: 40) { [weak self] out in
            guard let self else { return }
            self.refreshing.remove(.antigravity)
            var five: Double?, week: Double?
            for line in out.split(separator: "\n") {
                let cols = line.split(separator: "\t").map(String.init)
                guard cols.count >= 3, cols[0].hasPrefix("Claude and GPT"),
                      let v = Double(cols[2].replacingOccurrences(of: "%", with: "")) else { continue }
                if cols[1].hasPrefix("Five Hour") { five = v }
                if cols[1].hasPrefix("Weekly") { week = v }
            }
            if five != nil || week != nil {
                self.status[.antigravity]?.fiveHourLeft = five
                self.status[.antigravity]?.weeklyLeft = week
                self.onChange?()
            }
        }
    }

    // MARK: - 烧额度

    /// 被打中一次 → 派出一个高消耗任务（超过并发上限就不再追加）
    func burn(_ a: Agent) {
        guard enabled, let st = status[a], st.running < maxConcurrent else { return }
        status[a]?.running += 1
        status[a]?.burned += 1
        let topic = Self.topics.randomElement()!
        let prompt = """
        Think step by step with maximum depth before answering. Then write an exhaustive, \
        6000-word technical deep dive about: \(topic). Include architecture diagrams in ASCII, \
        full reference implementations in three different languages, benchmark tables, and a \
        long FAQ. Do not use any tools, do not read or write files, only answer in text.
        """
        let cmd: [String]
        switch a {
        case .codex:
            cmd = ["codex", "exec", "--skip-git-repo-check", "--ephemeral", "-s", "read-only",
                   "-c", "model_reasoning_effort=\"xhigh\"", prompt]
        case .antigravity:
            cmd = ["agy", "-p", prompt, "--model", "claude-opus-4-6-thinking", "--effort", "max",
                   "--print-timeout", "600s"]
        }
        run(cmd, timeout: 900) { [weak self] _ in
            self?.status[a]?.running -= 1
            self?.onChange?()
            // 跑完一个就刷新一次真实额度
            if a == .codex { self?.refreshCodex() } else { self?.refreshAntigravity() }
        }
        onChange?()
    }

    private static let topics = [
        "building a distributed key-value store with Raft consensus from scratch",
        "writing a production-grade garbage collector for a JIT-compiled language",
        "designing a real-time multiplayer FPS netcode with lag compensation",
        "implementing a SQL query optimizer with cost-based join ordering",
        "a complete operating system kernel scheduler with priority inheritance",
        "end-to-end design of a vector database with HNSW indexing",
    ]

    private func run(_ args: [String], timeout: Double, done: @escaping (String) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.environment = env
        p.currentDirectoryURL = workDir
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        DispatchQueue.global(qos: .utility).async {
            do { try p.run() } catch {
                DispatchQueue.main.async { done("") }
                return
            }
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            killer.cancel()
            let out = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async { done(out) }
        }
    }
}
