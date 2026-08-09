# AutoGo iOS (TrollStore)

iOS 自动化脚本引擎，支持 Lua / JavaScript 双脚本语言，通过 TCP 远程控制。

## 功能

- **Lua 脚本引擎** - 动态加载 liblua，执行 Lua 脚本
- **JavaScript 引擎** - 内置 JavaScriptCore，执行 JS 脚本
- **远程 Shell** - TCP 9999 端口，远程下发命令
- **OCR 文字识别** - Vision 框架屏幕文字识别
- **屏幕截图** - 获取屏幕截图 base64 编码
- **后台保活** - 静音音频保活机制

## Shell 命令

```
lua:<script>  执行 Lua 脚本
js:<script>   执行 JavaScript 脚本
ocr           屏幕 OCR 文字识别
capture       截图 (base64)
info          设备信息
help          帮助信息
exit          断开连接
```

## 构建

### 本地构建

```bash
./build.sh
```

生成 `build/output/AutoGo.ipa`

### GitHub Actions

Push 到 master/main 分支自动触发构建，IPA 从 Artifacts 下载。

## 安装

1. 下载 `AutoGo.ipa`
2. 通过 TrollStore 安装
3. 打开 App 后通过 TCP 9999 端口连接设备

## 连接示例

```bash
# telnet / netcat
nc <设备IP> 9999

# 执行 Lua
lua:print("Hello AutoGo")

# 执行 JS
js:1 + 2

# OCR
ocr
```
