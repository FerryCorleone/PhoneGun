<p align="center">
  <img src="docs/icon.png" width="128" alt="PhoneGun 图标">
</p>

<h1 align="center">PhoneGun · 手机打枪</h1>

<p align="center">把手机当成枪，转动手机瞄准 Mac 屏幕，打 Dock 和桌面上的图标。</p>

<p align="center">
  <a href="https://github.com/FerryCorleone/PhoneGun/releases/latest/download/PhoneGun.dmg"><b>⬇️ 下载 PhoneGun（macOS 14+）</b></a>
</p>

---

## 怎么玩

1. **安装**：打开下载的 `PhoneGun.dmg`，把 PhoneGun 拖进「应用程序」，然后打开它。
2. **授权**：第一次打开会弹窗，点「去打开」，系统设置会直接跳到对应页面，在列表里找到 PhoneGun，打开右边的开关就行（用来找到屏幕上的图标）。这个权限在 macOS 27 叫「设备控制和数据访问」，更早的系统叫「辅助功能」。
3. **拿起手机**：点菜单栏右上角的 **⌖**，用 iPhone 相机扫里面的二维码。
   - 手机和 Mac 要连同一个 Wi‑Fi；
   - Safari 提示「此连接非私人连接」时，点 **显示详细信息 → 访问此网站**。
4. **开打**：手机顶端对准屏幕点「回中」，转动手机瞄准，按红色按钮开火，甩一下手机换弹。

手机上不用装任何 App。

## 注意

- 打死**桌面上的文件**，它会被移到**废纸篓**（可以还原）。不想这样的话，在 ⌖ 菜单里取消勾选「击杀桌面文件后移到废纸篓」。
- 菜单里有个「打中 Codex / Antigravity 时真实消耗额度」，**默认关闭**。打开后，打中这两个 App 的图标会真的在后台烧它们的额度。

## 常见问题

- **手机打不开链接**：确认手机和 Mac 在同一个 Wi‑Fi。公司、学校的网络常常不让设备互连，可以改用手机热点。
- **用微信扫码打开很慢**：请用 iPhone 相机扫码，或者复制链接到 Safari 里打开。
- **准星方向反了或者太灵敏**：在 ⌖ 菜单里调「左右反向」「上下反向」和「灵敏度」。准星慢慢飘了，就点一下「回中」。

## 卸载

1. 点菜单栏的 **⌖ → 退出 PhoneGun**（它在运行时没法删除）；
2. 打开「应用程序」文件夹，把 PhoneGun 拖进废纸篓；
3. 想清理得更干净的话，可以再删掉 `~/Library/Application Support/PhoneGun`（网页扳机用的证书），并在 **系统设置 → 隐私与安全性 → 设备控制和数据访问**（旧系统叫「辅助功能」）里把 PhoneGun 移除。

## 自己编译

用 Xcode 打开 `PhoneGun.xcodeproj`，运行 `PhoneGunMac`。工程里还有一个可选的原生 iPhone 扳机 App `PhoneGunTrigger`，震动反馈比网页版更好。

## 致谢

- 换弹音效：[Handgun Reload Sound Effect](https://opengameart.org/content/handgun-reload-sound-effect)，作者 zer0_sol，CC0 协议
- 其余音效由代码实时合成，特效图片和图标由 AI 生成

## 许可证

[MIT](LICENSE)
