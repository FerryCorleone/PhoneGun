<p align="center">
  <img src="docs/icon.png" width="128" alt="PhoneGun 图标">
</p>

<h1 align="center">PhoneGun · 手机打枪</h1>

<p align="center">把手机变成玩具枪，转动手机瞄准 Mac 屏幕，射击 Dock 和桌面上的图标。</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-blue">
  <img alt="iOS 17+" src="https://img.shields.io/badge/iOS-17%2B-blue">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-orange">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

## 简介

PhoneGun 是一个恶搞向的桌面小游戏：

- Mac 上跑一个菜单栏小程序，在整个屏幕上叠一层透明的准星和特效；
- 手机当枪：用陀螺仪瞄准，按屏幕上的大红按钮开火，甩一下手机换弹；
- 能打的目标是 **Dock 里的 App** 和 **桌面上的文件**。命中有弹孔、血条、伤害数字、爆头和击杀提示，打死的 Dock 图标会变灰，打死的桌面文件会“飞”进废纸篓。

手机端有两种用法，**不装 App 也能玩**：

| 方式 | 需要什么 | 说明 |
|---|---|---|
| **网页扳机**（推荐） | 只要手机浏览器 | 扫 Mac 菜单栏里的二维码，用 Safari 打开就能玩 |
| 原生 iOS App「扳机」 | 用 Xcode 装到自己 iPhone | 震动反馈更细腻，延迟更低 |

## 功能

- 🎯 陀螺仪瞄准，One Euro 滤波防抖，可调灵敏度和方向
- 🔫 两把武器：手枪（半自动，15 发，伤害 25）和步枪（全自动，45 发，伤害 12），打中心区域算爆头，双倍伤害
- 💥 弹孔、火花、烟雾、血条、伤害数字、击杀播报、击杀暗角，Mac 和手机两边都有音效
- 🗑️ 打死桌面文件后真的移到废纸篓（可关）
- 🤖 打 AI Agent 的图标扣“额度”：打中 Codex / Antigravity 时，会在后台真实发起高消耗任务烧它们的额度（可关，详见[注意事项](#注意事项)）
- 📱 网页扳机：Mac 自带 HTTPS + WebSocket 服务，手机扫码即用，WebSocket 不通时自动改用 HTTP 轮询
- 🖱️ 鼠标测试模式：没有手机时用鼠标瞄准，<kbd>⌃</kbd><kbd>⌥</kbd><kbd>空格</kbd> 开火

## 快速开始

### 1. 编译运行 Mac 端

需要 macOS 14+ 和 Xcode 16+。

```bash
git clone https://github.com/FerryCorleone/PhoneGun.git
cd PhoneGun
xcodebuild -project PhoneGun.xcodeproj -scheme PhoneGunMac -configuration Release \
  -derivedDataPath build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
open build/Build/Products/Release/PhoneGun.app
```

也可以用 Xcode 打开 `PhoneGun.xcodeproj`，在 Signing 里换成自己的 Team，再运行 `PhoneGunMac`。

第一次启动会请求**辅助功能**权限，用来读取 Dock 和桌面图标的位置：
**系统设置 → 隐私与安全性 → 辅助功能**，打开 PhoneGun，然后重启 App。

> 上面的命令是用临时签名（ad-hoc）编译的，每次重新编译后系统会把它当成新 App，需要重新授权一次辅助功能。

### 2. 手机连上

**网页扳机（推荐）**

1. 手机和 Mac 连同一个 Wi‑Fi；
2. 点 Mac 菜单栏的 **⌖**，用 iPhone 相机扫菜单里的二维码；
3. Safari 会提示「此连接非私人连接」（证书是 Mac 自己生成的），点 **显示详细信息 → 访问此网站**；
4. 点「开始」，允许「动作与方向」权限。

> 请用 Safari 打开。微信、QQ 等 App 的内置浏览器可能很慢，或者拿不到陀螺仪。

**原生 App（可选）**

用 Xcode 打开工程，选择 `PhoneGunTrigger`，换成自己的 Team 后装到 iPhone。App 会通过 Bonjour 自动找到同一网络下的 Mac。

### 3. 开玩

1. 手机顶端对准屏幕中央，点 **回中**；
2. 转动手机瞄准，按红色按钮开火；
3. 子弹打完后甩一下手机（或点「换弹」）；
4. 打完了点「全部复活」。

## 菜单栏设置

| 选项 | 作用 |
|---|---|
| 准星回中 / 全部复活 | 和手机上的按钮一样 |
| 灵敏度 | 转多少度扫过整个屏幕（20°～70°，默认 40°） |
| 左右反向 / 上下反向 | 准星方向不对时用 |
| 打中 Codex / Antigravity 时真实消耗额度 | 默认开启 |
| 击杀桌面文件后移到废纸篓 | 默认开启 |
| Mac 也播放枪声 | Mac 端是否也放枪声 |
| 鼠标测试模式 | 不用手机，用鼠标瞄准 |

## 注意事项

> [!WARNING]
> 下面两个功能**默认开启**，会对你的电脑产生真实影响，第一次玩之前请先看一眼菜单。

- **打死桌面文件会移到废纸篓**。只针对 `~/Desktop` 里的文件和文件夹，不会直接删除，可以从废纸篓里还原。不想冒险的话，在菜单里关掉「击杀桌面文件后移到废纸篓」。
- **打中 Codex / Antigravity 会消耗真实额度**。每次命中会在后台调用 `codex exec` 或 `agy -p`，跑一个高推理强度的任务（最多同时 3 个）。没装这两个 CLI 就什么都不会发生。不想烧额度就关掉对应的菜单项。
- **网页扳机用的是自签名证书**，所以首次访问会有安全提示。证书保存在 `~/Library/Application Support/PhoneGun/`，局域网 IP 变化时会自动重新生成。服务只在局域网内监听 `47480` 端口。

## 工作原理

```
 ┌───────────── iPhone ─────────────┐          ┌──────────────── Mac ────────────────┐
 │ 原生 App：CoreMotion  ──UDP──────┼──────────┼▶ GameServer (47474/udp, Bonjour)   │
 │ 网页扳机：DeviceOrientation      │          │                                     │
 │           ──WSS / HTTPS 轮询─────┼──────────┼▶ WebServer  (47480/tcp, TLS)       │
 └──────────────────────────────────┘          │      │                              │
                                               │      ▼                              │
                                               │   Game：瞄准换算、命中判定、血量     │
                                               │      │                              │
                                               │      ├─ TargetScanner（辅助功能 API）│
                                               │      ├─ Overlay（透明窗口 + CALayer）│
                                               │      └─ Quota（读取/消耗 AI 额度）   │
                                               └─────────────────────────────────────┘
```

- **瞄准**：手机算出机身顶端在世界坐标里的朝向（yaw / pitch），每秒约 60～100 次发给 Mac；Mac 以「回中」那一刻的朝向为屏幕中心换算准星位置，再用 One Euro 滤波平滑。
- **目标识别**：用辅助功能 API 读取 Dock 项和 Finder 桌面图标的位置，每 1.5 秒刷新一次。
- **特效**：每块屏幕一个透明、鼠标可穿透、置顶的窗口，全部用 CALayer 绘制。

### 通信协议

一行一条文本消息，UDP 和 WebSocket 通用：

| 方向 | 消息 | 含义 |
|---|---|---|
| 手机 → Mac | `A <yaw> <pitch>` | 当前朝向（弧度） |
| | `R` | 回中 |
| | `F <id> <weapon>` | 开火（`pistol` / `rifle`），Mac 按 id 去重 |
| | `V` | 全部复活 |
| | `P` | 心跳 |
| Mac → 手机 | `H <damage> <headshot>` | 命中 |
| | `K <name>` | 击杀 |
| | `M` | 未命中 |

## 项目结构

```
├── Mac/                  # 菜单栏 App（PhoneGunMac）
│   ├── main.swift        #   菜单栏和设置菜单
│   ├── Game.swift        #   游戏逻辑：瞄准、命中、血量、击杀
│   ├── GameServer.swift  #   UDP + Bonjour 服务（原生 App 用）
│   ├── WebServer.swift   #   HTTPS + WebSocket 服务（网页扳机用）
│   ├── WebCert.swift     #   自签名证书生成
│   ├── Web/trigger.html  #   网页扳机页面
│   ├── Targets.swift     #   扫描 Dock 和桌面图标
│   ├── Overlay.swift     #   全屏特效层
│   ├── Quota.swift       #   Codex / Antigravity 额度读取和消耗
│   └── ...
├── iOS/                  # 原生扳机 App（PhoneGunTrigger）
├── Shared/               # 两端共用：通信协议、合成音效、音频素材
├── project.yml           # XcodeGen 配置
└── PhoneGun.xcodeproj
```

改了 `project.yml` 之后用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 重新生成工程：

```bash
xcodegen generate
```

## 常见问题

**网页扳机打不开 / 一直在连接**
确认手机和 Mac 在同一个 Wi‑Fi 下，并且 Mac 菜单里显示的 IP 和你打开的地址一致。公司或校园网经常开着设备隔离，手机连不到电脑，可以换成手机热点试试。

**提示「没收到陀螺仪数据」**
必须用 `https://` 打开，并在点「开始」后允许「动作与方向」权限。如果之前点过拒绝，要把这个网页关掉重新打开。

**准星方向反了 / 太灵敏**
在菜单里调「左右反向」「上下反向」和灵敏度。玩久了准星会慢慢偏，点一下「回中」就好。

**一个目标都识别不到**
检查有没有给 PhoneGun 开辅助功能权限，开了之后要重启 App。

## 已知限制

- 只支持 macOS，目标识别依赖 Dock 和 Finder 的辅助功能接口；
- iOS Safari 没有正式的震动 API，网页扳机只能借系统开关控件的触感模拟，效果比原生 App 弱；
- 手机和 Mac 需要在同一个局域网内。

## 参与贡献

欢迎提 Issue 和 PR。比较大的改动建议先开个 Issue 聊聊思路。

## 许可证

[MIT](LICENSE)
