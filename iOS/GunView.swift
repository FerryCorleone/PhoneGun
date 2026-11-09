import SwiftUI

struct GunView: View {
    @EnvironmentObject var gun: GunModel
    @State private var pressed = false
    @State private var flash = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                RadialGradient(colors: [Color.red.opacity(flash ? 0.45 : 0), .clear],
                               center: .center, startRadius: 10, endRadius: geo.size.height * 0.7)
                    .ignoresSafeArea()
                    .animation(.easeOut(duration: 0.25), value: flash)

                VStack(spacing: 18) {
                    header
                    Picker("武器", selection: $gun.weapon) {
                        ForEach(Weapon.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text(gun.lastResult.isEmpty ? "顶端对准屏幕按「回中」· 甩一下换弹" : gun.lastResult)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(gun.lastResult.hasPrefix("击杀") ? .red
                                         : gun.lastResult.hasPrefix("爆头") ? .yellow : .white)
                        .frame(height: 30)

                    ZStack {
                        HitMarkerView(kind: gun.hitKind, visible: flash)
                    }
                    .frame(maxHeight: .infinity)

                    HStack(spacing: 14) {
                        smallButton("全部复活", "heart.fill") { gun.reviveAll() }
                    }

                    HStack(spacing: 14) {
                        bigButton("回中", "scope", .blue) { gun.recenter() }
                        bigButton(gun.reloading ? "换弹中" : "换弹", "arrow.triangle.2.circlepath", .orange) { gun.reload() }
                    }

                    trigger(size: min(geo.size.width * 0.72, 300))
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 20)
            }
        }
        .onChange(of: gun.hitFlash) {
            flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { flash = false }
        }
    }

    private var header: some View {
        HStack {
            LinkStatus(link: gun.link)
            Spacer()
            Label("\(gun.kills)", systemImage: "scope").font(.headline).foregroundStyle(.red)
            Text("\(gun.ammo)/\(gun.weapon.magazine)")
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(gun.ammo == 0 ? .red : .white)
        }
        .padding(.top, 8)
    }

    private func bigButton(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(color.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(color, lineWidth: 1.5))
        }
        .foregroundStyle(.white)
    }

    private func smallButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .foregroundStyle(.white.opacity(0.85))
    }

    private func trigger(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.25, blue: 0.2), Color(red: 0.55, green: 0, blue: 0)],
                                         center: .center, startRadius: 5, endRadius: size / 2))
            Circle().stroke(Color.white.opacity(0.85), lineWidth: 4)
            VStack(spacing: 4) {
                Image(systemName: "flame.fill").font(.system(size: 44))
                Text("开火").font(.system(size: 30, weight: .black))
            }
            .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .scaleEffect(pressed ? 0.93 : 1)
        .shadow(color: .red.opacity(pressed ? 0.9 : 0.4), radius: pressed ? 30 : 14)
        .animation(.spring(response: 0.12, dampingFraction: 0.5), value: pressed)
        // 用 DragGesture(minimumDistance: 0) 拿到“按下”瞬间，比 Button 的松手触发快
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !pressed { pressed = true; gun.triggerDown() } }
            .onEnded { _ in pressed = false; gun.triggerUp() })
    }
}

/// 手机上同步显示命中标记（白=命中，金=爆头，红=击杀）
private struct HitMarkerView: View {
    let kind: Int
    let visible: Bool
    var body: some View {
        let color: Color = kind == 2 ? .red : kind == 1 ? Color(red: 1, green: 0.84, blue: 0.3) : .white
        let r: CGFloat = kind == 2 ? 46 : 34
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            var p = Path()
            for (dx, dy) in [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)] {
                p.move(to: CGPoint(x: c.x + dx * r * 0.4, y: c.y + dy * r * 0.4))
                p.addLine(to: CGPoint(x: c.x + dx * r, y: c.y + dy * r))
            }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: kind == 2 ? 7 : 5, lineCap: .round))
        }
        .frame(width: 120, height: 120)
        .scaleEffect(visible ? 1 : 1.4)
        .opacity(visible ? 1 : 0)
        .animation(visible ? .easeOut(duration: 0.05) : .easeOut(duration: 0.3), value: visible)
    }
}

private struct LinkStatus: View {
    @ObservedObject var link: Link
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(link.connected ? .green : .orange).frame(width: 9, height: 9)
            Text(link.status).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
