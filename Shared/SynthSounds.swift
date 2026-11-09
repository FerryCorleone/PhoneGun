import AVFoundation

/// 程序化合成的音效，不依赖音频素材文件。
enum SoundKind: CaseIterable {
    case gunshot, rifleShot, hit, headshot, kill, empty, reload, killDing, whoosh, trashThud
}

final class SoundBoard {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [SoundKind: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    init(voices: Int = 10) {
        for _ in 0..<voices {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        for k in SoundKind.allCases { buffers[k] = Self.render(k, format: format) }
        // 有真实录音素材就用素材（Sounds/<名字>.wav，单声道 44.1k）
        for (k, name) in [(SoundKind.reload, "reload")] {
            if let b = Self.loadSample(name, format: format) { buffers[k] = b }
        }
        start()
    }

    func start() {
        guard !engine.isRunning else { return }
        do { try engine.start(); players.forEach { $0.play() } } catch { print("audio:", error) }
    }

    /// pan: -1 左 … 1 右
    func play(_ kind: SoundKind, volume: Float = 1, pan: Float = 0) {
        start()
        guard let buf = buffers[kind] else { return }
        let p = players[next]; next = (next + 1) % players.count
        p.stop()
        p.volume = volume
        p.pan = max(-1, min(1, pan))
        p.scheduleBuffer(buf, at: nil, options: [])
        p.play()
    }

    private static func loadSample(_ name: String, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              file.processingFormat.sampleRate == format.sampleRate,
              file.processingFormat.channelCount == format.channelCount,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil else { return nil }
        return buf
    }

    // MARK: - synthesis

    private static func render(_ kind: SoundKind, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sr = Float(format.sampleRate)
        let dur: Float
        switch kind {
        case .gunshot: dur = 0.45
        case .rifleShot: dur = 0.25
        case .hit: dur = 0.09
        case .headshot: dur = 0.22
        case .kill: dur = 1.1
        case .empty: dur = 0.05
        case .reload: dur = 0.45
        case .killDing: dur = 0.5
        case .whoosh: dur = 0.8
        case .trashThud: dur = 0.5
        }
        let n = AVAudioFrameCount(dur * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buf.frameLength = n
        let out = buf.floatChannelData![0]
        var lp: Float = 0, lp2: Float = 0
        var seed: UInt32 = 0x1234_5678
        func noise() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) * 2 - 1 }
        let twoPi = Float.pi * 2

        for i in 0..<Int(n) {
            let t = Float(i) / sr
            var s: Float = 0
            switch kind {
            case .gunshot, .rifleShot:
                let k: Float = kind == .gunshot ? 1 : 1.6
                let nz = noise()
                let cutoff: Float = 0.08 + 0.9 * exp(-t * 30 * k)  // 越来越闷
                lp += (nz - lp) * cutoff
                let crack = nz * exp(-t * 140) * 0.9
                let body = lp * exp(-t * 11 * k) * 1.2
                let thump = sin(twoPi * (55 + 90 * exp(-t * 25)) * t) * exp(-t * 14 * k) * 0.9
                s = crack + body + thump
            case .hit:
                s = sin(twoPi * 2100 * t) * exp(-t * 55) * 0.6 + noise() * exp(-t * 120) * 0.35
            case .headshot:
                s = (sin(twoPi * 1500 * t) + sin(twoPi * 3020 * t) * 0.6) * exp(-t * 18) * 0.45
                    + noise() * exp(-t * 90) * 0.3
            case .kill:
                let nz = noise()
                lp += (nz - lp) * 0.06
                lp2 += (lp - lp2) * 0.2
                let boom = sin(twoPi * (35 + 70 * exp(-t * 6)) * t) * exp(-t * 3.5) * 1.0
                s = lp2 * 6 * exp(-t * 3) + boom + nz * exp(-t * 40) * 0.5
            case .empty:
                s = noise() * exp(-t * 300) * 0.6 + sin(twoPi * 3500 * t) * exp(-t * 200) * 0.3
            case .killDing:
                // 击杀确认“叮”：两个音叠一下
                let a = sin(twoPi * 1320 * t) * exp(-t * 7)
                let t2 = max(0, t - 0.06)
                let b = t > 0.06 ? sin(twoPi * 1980 * t2) * exp(-t2 * 6) : 0
                s = (a * 0.45 + b * 0.4) * (1 - exp(-t * 400))
            case .whoosh:
                // 呼——：带通噪声，音高先升后降
                let nz = noise()
                let env = sin(Float.pi * min(1, t / 0.8)) * sin(Float.pi * min(1, t / 0.8))
                let k: Float = 0.05 + 0.25 * env
                lp += (nz - lp) * k
                lp2 += (lp - lp2) * k
                s = (lp - lp2) * 5 * env
            case .trashThud:
                let nz = noise()
                lp += (nz - lp) * 0.1
                s = sin(twoPi * (90 + 60 * exp(-t * 20)) * t) * exp(-t * 12) * 0.9
                    + lp * exp(-t * 9) * 1.5
                    + (t > 0.05 ? noise() * exp(-(t - 0.05) * 30) * 0.25 : 0)
            case .reload:
                let c1 = t < 0.05 ? noise() * exp(-t * 200) : 0
                let t2 = t - 0.28
                let c2 = t2 > 0 ? (noise() * 0.7 + sin(twoPi * 1800 * t2) * 0.5) * exp(-t2 * 120) : 0
                s = (c1 + c2) * 0.8
            }
            out[i] = max(-1, min(1, s * 0.8))
        }
        return buf
    }
}
