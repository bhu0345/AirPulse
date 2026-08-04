# AirPulse 前置条件

本机在开发启动时的状态：

| 项 | 状态 |
|----|------|
| macOS | 26.5.1（Darwin 25.5.0） |
| 机型 | MacBook Pro M5 Pro（`Mac17,9`） |
| Xcode.app | **未安装**（仅有 Command Line Tools） |
| 代码签名证书 | **0 valid identities** |
| Swift | 6.3.3（CLT） |

## 必须完成（才能用特权 Helper 正式控风扇）

1. **安装完整 Xcode**（App Store 或 [developer.apple.com](https://developer.apple.com/download/)）
   ```bash
   # 安装后切换工具链：
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   ```

2. **配置代码签名**
   - 本地调试：用免费 Apple ID 登录 Xcode → Settings → Accounts，生成 Development 证书。
   - 长期安装 `SMAppService` 特权 Helper：通常需要付费 **Apple Developer Program**。
   - 当前仓库也提供 **LaunchDaemon + sudo** 安装路径（见 `Scripts/install-helper.sh`），个人自用可不依赖 Developer ID。

3. **开发期请退出 Macs Fan Control**，避免两个进程抢写同一组 SMC key。

## 当前工程在无 Xcode 时仍可做什么

- 用 CLT + `swift build` 编译 `SMCKit` / `FanKit` / CLI / Helper / App。
- 用 CLI 做 **SMC 只读探针**（风扇 RPM、温度）。
- 用 `sudo` 跑 CLI 做 **写转速可行性验证**。
- SwiftUI 菜单栏 App 可打包为 `.app`（见 `Scripts/build-app.sh`）。

签名与 Xcode 就绪后，把 `CODE_SIGN_IDENTITY` / `DEVELOPMENT_TEAM` 写入 `Config/local.xcconfig`（可选，面向 Xcode 工程），或继续使用 LaunchDaemon 安装方式。

## Gatekeeper / 公证（可选）

本机若 **0 valid identities**，`Scripts/build-app.sh` 仍用 **ad-hoc** 签名（本机可用，首次需右键打开）。

对外分发且希望双击即可打开，需要：

1. Apple Developer Program + **Developer ID Application** 证书  
2. `xcrun notarytool store-credentials …` 建好钥匙串 profile  
3. 构建后运行：

```bash
./Scripts/build-app.sh
./Scripts/sign-and-notarize.sh
./Scripts/package-dmg.sh 0.2.0
```

无证书时脚本会直接报错并打印上述步骤，不会假装公证成功。
