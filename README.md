# iOS 实时消息弹窗与强提醒应用 (巨魔免签方案)

## 一、 项目背景与架构理念

本项目针对 **无苹果付费开发者账号（免 $99/年）** 且设备安装有 **TrollStore（巨魔）** 的场景，开发一款专用的 iOS 客户端。

常规 App Store 应用由于系统沙盒限制，后台会被强制休眠，通常必须依赖苹果 APNs（Apple Push Notification service）推送。而借助 TrollStore 突破沙盒特权的能力，本项目采用 **“真·后台长连接 + 系统本地通知（Local Notification）”** 架构：
1. **零成本免签**：无需付费开发者证书。
2. **真后台常驻**：通过巨魔私有权限保证 App 在后台或锁屏状态下不被 iOS 挂起杀掉。
3. **极低延迟**：客户端与自家服务器点对点保持 WebSocket 通道，毫秒级响应。
4. **系统级强提醒**：收到消息后触发原生本地通知，支持顶部横幅弹窗、锁屏亮屏、自定义铃声震动。

---

## 二、 整体技术架构

```
┌─────────────────────┐
│    自建业务服务端     │
│ (Node.js / Python)  │
└──────────┬──────────┘
           │ 保持 WebSocket 长连接 (心跳保活)
           ▼
┌─────────────────────────────────────────────────────────┐
│  iPhone (TrollStore 巨魔环境)                           │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │ 本应用 (常驻后台，持有无限后台 Entitlement)         │  │
│  │ 1. 监听 WebSocket 消息通道                        │  │
│  │ 2. 收到消息立即组装本地通知 Payload                │  │
│  └───────────────────────┬───────────────────────────┘  │
│                          │ 派发本地通知请求               │
│                          ▼                              │
│  ┌───────────────────────────────────────────────────┐  │
│  │ iOS 系统通知中心 (UNUserNotificationCenter)        │  │
│  │ - 唤醒屏幕 / 锁屏显示                              │  │
│  │ - 顶部横幅弹窗 (Banner)                           │  │
│  │ - 播放自定义音频 (.caf/.wav)                      │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## 三、 全流程工作路线图 (Roadmap)

### 第一阶段：开发环境与基础工程初始化
- [ ] **确定编译环境**：
  - 推荐：Mac + Xcode（最标准的原生开发环境，使用免费个人 Apple ID 即可调试）。
  - 备选：Windows 下使用 Flutter / React Native 跨平台方案结合无证书打包，或使用 GitHub Actions 免费云端 macOS Runner 自动编译产出 `.ipa`。
- [ ] **创建工程**：
  - 创建原生 iOS (Swift + SwiftUI / UIKit) 项目。
  - 准备提示音资源文件（如 `alert.wav` / `alert.caf`，时长 < 30 秒，放入 App Bundle 资源目录）。

### 第二阶段：iOS 客户端核心功能开发
- [ ] **Step 1: 系统通知权限请求**
  - 启动阶段调用 `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])`。
  - 引导用户允许“横幅、声音、标记、锁屏显示”。
- [ ] **Step 2: 注入巨魔后台常驻权限（Entitlements）**
  - 在 Xcode 的 Entitlements 配置文件中添加无限制后台权限支持（例如 `com.apple.multitasking.unlimited` 或系统级后台音频/定位特权标签）。
  - 确保 App 退到后台或锁屏后，系统调度器不会暂停其 CPU 运行与网络连接。
- [ ] **Step 3: WebSocket 长连接与重连机制**
  - 封装轻量长连接客户端（基于系统原生 `URLSessionWebSocketTask` 或 `Starscream`）。
  - 增加网络监听与断线指数退避重连机制（Network Reachability Reconnect）。
  - 设置 30~60 秒轻量心跳（Ping/Pong），既能防运营商 NAT 断流，又不过度消耗手机电量。
- [ ] **Step 4: 本地强通知触发器 (Local Notification Dispatcher)**
  - 监听收到 JSON 消息（如 `{ "title": "交易预警", "body": "触发风控阈值！", "sound": "alert.caf" }`）。
  - 创建 `UNMutableNotificationContent`，填充标题、正文与声音。
  - 创建触发器 `UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)` 立即提交系统展示。
- [ ] **Step 5: (可选) 持续震动与音量保底**
  - 如果通知声音可能被环境噪音盖过，可配合后台 `AVAudioPlayer` 实现持续高音量响铃，直至用户在 UI 上点击确认。

### 第三阶段：测试后端服务端搭建
- [ ] **搭建最小化 WebSocket 服务**：
  - 技术栈：Node.js（`ws` 库）或 Python（`fastapi` / `websockets`）。
  - 功能：
    1. 维持与 iPhone 客户端的连接状态管理。
    2. 提供 HTTP API 或简易 Web 界面，随时点击即可下发测试消息。

### 第四阶段：无证书编译与 IPA 打包
- [ ] **编译产物**：
  - 在 Xcode 中执行构建，生成 `YourApp.app` 文件。
- [ ] **打包标准 IPA**：
  - 新建 `Payload/` 目录并将 `YourApp.app` 复制入内。
  - 命令行打包：`zip -r -y YourApp.ipa Payload`。
  - 检查并保留自定义注入的特权 Entitlements 声明。

### 第五阶段：巨魔安装、联调与性能调优
- [ ] **安装测试**：
  - 将 `YourApp.ipa` 发送到 iPhone，选择“使用 TrollStore 打开”安装。
- [ ] **场景化实测**：
  - **前台测试**：确认点击测试按钮能收到即时弹窗和声音。
  - **切后台与锁屏测试**：将手机熄屏放置 10 分钟、30 分钟、数小时，从服务端下发消息，验证能否准时亮屏、弹窗并响铃。
  - **网络切换测试**：从 Wi-Fi 切换到 4G/5G，验证 WebSocket 自动重连是否稳健。
- [ ] **功耗与保活调优**：
  - 观察后台耗电排行，确保心跳频率适中，无死循环或高 CPU 占用。

---

## 四、 核心注意点与避坑指南

1. **勿扰模式与专注模式**：
   - iOS 15+ 引入了专注模式（Focus Mode）。为了确保通知必达，可在生成本地通知时设置 `content.interruptionLevel = .timeSensitive`（时间敏感通知），可在用户开启勿扰时穿透提醒。
2. **手机物理静音键**：
   - 普通本地通知遵循物理静音键。如果需要“即使拨了静音开关也必须最大声报警”，可通过后台运行机制配合 `AVAudioSession(category: .playback)` 强制输出音频。
3. **断网重连**：
   - 移动网络在基站切换时可能存在瞬时假死，必须实现心跳超时自动主动重连机制。
