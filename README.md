# AutoGo iOS 巨魔版

> AutoGo 的 iOS 巨魔商店（TrollStore）版本，支持在前台画面找色、获取前台应用包名、模拟点击/滑动、OCR 文字识别，以及通过 HTTP Web UI 远程控制。

---

## 功能特性

| 功能 | 状态 | 说明 |
|------|------|------|
| 🎨 找色/找图 | ✅ | 基于 IOSurface 帧缓冲，支持多点找色、相似度容差 |
| 📱 前台应用包名 | ✅ | 4 级降级方案，优先 SBApplicationController |
| 👆 点击/滑动 | ✅ | 底层 IOHIDEvent，跨应用稳定 |
| 🔤 OCR | ✅ | Vision 框架，支持中/英/日/韩 |
| 🌐 HTTP Web UI | ✅ | 内置 Web 控制台 + REST API |
| 🎈 悬浮球 | ✅ | 快速暂停/继续/查看日志 |

---

## 本地构建

### 环境要求

- macOS 10.15+
- Xcode 12.0+（建议 14.0+）
- [xcodegen](https://github.com/yonaskolb/XcodeGen)
- [ldid](https://github.com/ProcursusTeam/ldid)（巨魔签名用）

### 构建步骤

```bash
# 1. 进入项目目录
cd AutoGo-iOS

# 2. 安装依赖（如未安装）
brew install xcodegen ldid

# 3. 生成 Xcode 项目
xcodegen generate --spec project.yml

# 4. 构建并打包 IPA（无需 Apple 开发者账号）
./build.sh

# 5. 构建产物位于
#    build/AutoGo.ipa
```

---

## GitHub 网页自动构建（推荐）

本项目已配置 GitHub Actions，**无需 Mac 电脑**，直接在 GitHub 网页上即可构建 IPA。

### 配置步骤

1. **Fork 本仓库** 到你自己的 GitHub 账号下
2. 进入仓库的 **Actions** 页面
3. 点击左侧 **Build AutoGo iOS IPA**
4. 点击 **Run workflow** 按钮，即可手动触发构建
5. 构建完成后，在 **Actions 运行详情页 → Artifacts** 中下载 IPA

### 自动发布

当代码推送到 `main` 分支时，GitHub Actions 会自动构建并创建一个 Pre-release Release，IPA 会作为附件发布。你可以直接在 Release 页面下载。

---

## 安装到 iPhone

1. 在 iPhone 上安装 [TrollStore 巨魔商店](https://github.com/opa334/TrollStore)
2. 把 `AutoGo.ipa` 传到手机（AirDrop、文件共享、iCloud 等）
3. 用 TrollStore 打开 IPA 并安装

---

## 使用方式

### Web 控制台

安装完成后，确保手机和电脑在同一 WiFi：

```
http://<手机IP>:8989/
```

打开后即可看到 Web 控制台，支持：
- 点击/滑动/长按
- 找色
- OCR
- 查看前台应用
- 截图

### REST API

| 端点 | 参数 | 说明 |
|------|------|------|
| `GET /touch/tap` | `x`, `y` | 点击 |
| `GET /touch/swipe` | `x1`, `y1`, `x2`, `y2`, `duration` | 滑动 |
| `GET /screen/findcolor` | `color`, `tolerance` | 找色 |
| `GET /app/foreground` | — | 前台应用信息 |
| `GET /ocr/recognize` | — | OCR 识别 |

更多 API 见源码 `AutoGo/Core/AutoGoCore.swift`。

---

## 权限说明

本应用依赖 TrollStore 注入以下关键私有权限：

```xml
<key>com.apple.private.hid.client.event-dispatch</key>
<true/>
<key>com.apple.private.IOSurface.CAMetalLayer</key>
<true/>
<key>platform-application</key>
<true/>
<key>com.apple.private.security.no-container</key>
<true/>
```

**未安装 TrollStore 的设备无法使用。**

---

## 目录结构

```
AutoGo-iOS/
├── .github/workflows/build.yml   # GitHub Actions 自动构建
├── project.yml                  # XcodeGen 项目定义
├── build.sh                     # 本地构建脚本
├── AutoGo.xcconfig              # 构建覆盖配置
├── AutoGo/
│   ├── AppDelegate.swift        # 应用入口 + 后台保活
│   ├── BridgeHeader.h           # ObjC 桥接头文件
│   ├── BridgeImplementation.m   # IOKit / IOSurface 桥接实现
│   ├── AutoGo.entitlements      # 巨魔权限声明
│   ├── Info.plist
│   ├── Core/                    # 核心功能
│   ├── Server/                  # HTTP 服务
│   ├── UI/                      # 界面
│   └── Resources/               # 资源 + Web UI
└── README.md
```

---

## 免责声明

本项目仅供学习研究 iOS 自动化技术使用。使用本工具进行操作可能违反某些应用的服务条款，请自行承担风险。

---

## 致谢

- [TrollStore](https://github.com/opa334/TrollStore)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [ldid](https://github.com/ProcursusTeam/ldid)
